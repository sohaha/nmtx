"""Offline contracts: python3 -m unittest discover -s scripts -p 'test_*.py'.

Requires PyYAML (python3 -m pip install PyYAML).
"""

import os
import re
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


def workflow(name):
    # Keep GitHub's YAML 1.2 `on` key and scalar spelling intact.
    return yaml.load((ROOT / ".github/workflows" / name).read_text(), Loader=yaml.BaseLoader)


class ReleaseContracts(unittest.TestCase):
    def test_combined_release_pins_source_and_calls_both_products(self):
        release = workflow("zeno-release.yml")
        inputs = release["on"]["workflow_dispatch"]["inputs"]
        self.assertEqual(inputs["publish"]["default"], "true")
        self.assertEqual(inputs["retain"]["default"], "2")
        jobs = release["jobs"]
        self.assertEqual(set(jobs), {"resolve", "server", "computer"})
        for product in ("server", "computer"):
            job = jobs[product]
            self.assertEqual(job["needs"], "resolve")
            self.assertEqual(job["uses"], f"./.github/workflows/zeno-{product}.yml")
            self.assertEqual(job["secrets"], "inherit")
            self.assertEqual(job["with"]["source_ref"], "${{ needs.resolve.outputs.source_sha }}")
            for key in ("version", "channel", "publish", "retain", "github_release"):
                self.assertEqual(job["with"][key], "${{ inputs." + key + " }}")
        self.assertEqual(release["permissions"], {"contents": "read"})

    def test_readme_upload_is_markdown_and_revalidated(self):
        for product in ("server", "computer"):
            steps = workflow(f"zeno-{product}.yml")["jobs"]["publish-r2"]["steps"]
            upload = next(step["run"] for step in steps if step.get("name") == "Upload to Cloudflare R2")
            # Execute only the pure header functions, never the actual upload.
            functions = "\n".join(re.search(rf"(?ms)^{name}\(\) \{{.*?^\}}", upload).group()
                                  for name in ("content_type", "cache_control"))
            for path, mime, cache in (
                ("README.md", "text/markdown; charset=utf-8", "no-cache, must-revalidate"),
                ("install.sh", "text/x-shellscript", "public, max-age=3600"),
                ("manifest.json", "application/json", "no-cache, must-revalidate"),
                ("0.0.1/binary", "application/octet-stream", "public, max-age=31536000, immutable"),
            ):
                with self.subTest(product=product, path=path):
                    result = subprocess.run(["bash", "-c", functions + '\ncontent_type "$1"; echo; cache_control "$1"',
                                             "headers", path], capture_output=True, text=True, check=True)
                    self.assertEqual(result.stdout, mime + "\n" + cache)

    def test_standalone_inputs_are_also_callable(self):
        for product in ("server", "computer"):
            triggers = workflow(f"zeno-{product}.yml")["on"]
            self.assertIn("repository_dispatch", triggers)
            direct = triggers["workflow_dispatch"]["inputs"]
            reusable = triggers["workflow_call"]["inputs"]
            self.assertEqual(set(direct), set(reusable))
            for key in direct:
                for attribute in ("type", "required"):
                    self.assertEqual(direct[key].get(attribute), reusable[key].get(attribute))
                if reusable[key].get("required") == "true":
                    self.assertNotIn("default", reusable[key])
                else:
                    self.assertEqual(direct[key].get("default"), reusable[key].get("default"))

    def test_concurrency_and_artifacts_are_isolated(self):
        groups = []
        artifacts = []
        for product in ("server", "computer"):
            data = workflow(f"zeno-{product}.yml")
            group = data["concurrency"]["group"]
            self.assertNotIn("github.workflow", group)
            groups.append(group)
            upload = next(step for step in data["jobs"]["build"]["steps"]
                          if step.get("uses", "").startswith("actions/upload-artifact@"))
            download = next(step for step in data["jobs"]["package"]["steps"]
                            if step.get("uses", "").startswith("actions/download-artifact@"))
            prefix = f"zeno-{product}-sea-"
            self.assertTrue(upload["with"]["name"].startswith(prefix))
            self.assertEqual(download["with"]["pattern"], prefix + "*")
            artifacts.append(upload["with"]["name"])
        groups.append(workflow("zeno-release.yml")["concurrency"]["group"])
        self.assertEqual(len(set(groups)), 3)
        self.assertEqual(len(set(artifacts)), 2)


class SourceResolution(unittest.TestCase):
    def test_branch_tag_sha_and_commit_url_resolve_to_same_commit(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory) / "source"
            repo.mkdir()

            def git(*args):
                return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()

            git("init", "-q", "-b", "dev")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "fixture")
            sha = git("rev-parse", "HEAD")
            git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                "-c", "tag.gpgsign=false", "tag", "-a", "v1.2.3", "-m", "fixture")
            env = {**os.environ, "CNB_TOKEN": "offline-fixture", "SOURCE_URL": str(repo)}
            script = ROOT / "scripts/zeno-resolve-source.sh"
            for ref in ("dev", "v1.2.3", sha,
                        f"https://cnb.cool/zls_nmtx/sohaha/bots/-/commit/{sha}/"):
                with self.subTest(ref=ref):
                    result = subprocess.run(["bash", str(script)], env={**env, "SOURCE_REF": ref},
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout.strip(), sha)
            for ref in ("--upload-pack=bad", "bad ref", "missing-branch"):
                result = subprocess.run(["bash", str(script)], env={**env, "SOURCE_REF": ref},
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
