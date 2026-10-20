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
RELEASE_WORKFLOW = "zeno-release.yml"
PRODUCTS = ("server", "computer")


def workflow(name):
    # Keep GitHub's YAML 1.2 `on` key and scalar spelling intact.
    return yaml.load((ROOT / ".github/workflows" / name).read_text(), Loader=yaml.BaseLoader)


def release_workflow():
    return workflow(RELEASE_WORKFLOW)


def job_steps(data, job):
    return data["jobs"][job]["steps"]


def step_named(steps, name):
    return next(step for step in steps if step.get("name") == name)


def artifact_step(data, job, action):
    return next(step for step in job_steps(data, job)
                if step.get("uses", "").startswith(action))


class ReleaseContracts(unittest.TestCase):
    def test_release_is_one_dispatch_only_workflow(self):
        release = release_workflow()
        triggers = release["on"]
        # One entry point: no reusable-call or repository_dispatch surface left.
        self.assertEqual(set(triggers), {"workflow_dispatch"})
        inputs = triggers["workflow_dispatch"]["inputs"]
        self.assertEqual(inputs["publish"]["default"], "true")
        self.assertEqual(inputs["retain"]["default"], "2")
        for key in ("source_ref", "version"):
            self.assertEqual(inputs[key]["required"], "true")
        for key in ("release_tag", "channel", "publish", "github_release", "retain"):
            self.assertEqual(inputs[key]["required"], "false")
        self.assertEqual(release["permissions"], {"contents": "read"})
        # No job delegates to a reusable workflow anymore.
        self.assertFalse([j for j in release["jobs"].values() if "uses" in j])

    def test_release_job_graph_covers_both_products(self):
        jobs = release_workflow()["jobs"]
        self.assertEqual(set(jobs), {
            "resolve",
            "server-web",
            "server-build",
            "server-package",
            "server-publish-r2",
            "computer-build",
            "computer-package",
            "computer-publish-r2",
            "computer-publish-github",
        })
        expected_needs = {
            "server-web": "resolve",
            "server-build": ["resolve", "server-web"],
            "server-package": ["resolve", "server-build"],
            "server-publish-r2": ["resolve", "server-package"],
            "computer-build": "resolve",
            "computer-package": ["resolve", "computer-build"],
            "computer-publish-r2": ["resolve", "computer-package"],
            "computer-publish-github": ["resolve", "computer-package"],
        }
        for job, needs in expected_needs.items():
            self.assertEqual(jobs[job]["needs"], needs, job)
        # Both publish legs gate on the shared resolve output.
        self.assertEqual(jobs["server-publish-r2"]["if"], "needs.resolve.outputs.publish == 'true'")
        self.assertEqual(
            jobs["computer-publish-github"]["if"],
            "needs.resolve.outputs.publish == 'true' && needs.resolve.outputs.github_release == 'true'",
        )

    def test_readme_upload_is_markdown_and_revalidated(self):
        data = release_workflow()
        for product in PRODUCTS:
            upload = step_named(job_steps(data, f"{product}-publish-r2"),
                                "Upload to Cloudflare R2")["run"]
            # Execute only the pure header functions, never the actual upload.
            functions = "\n".join(re.search(rf"(?ms)^{name}\(\) \{{.*?^\}}", upload).group()
                                  for name in ("content_type", "cache_control"))
            for path, mime, cache in (
                ("README.md", "text/markdown; charset=utf-8", "no-cache, must-revalidate"),
                ("install.sh", "text/x-shellscript", "public, max-age=3600"),
                ("uninstall.sh", "text/x-shellscript", "public, max-age=3600"),
                ("uninstall.ps1", "text/plain; charset=utf-8", "public, max-age=3600"),
                ("manifest.json", "application/json", "no-cache, must-revalidate"),
                ("0.0.1/binary", "application/octet-stream", "public, max-age=31536000, immutable"),
            ):
                with self.subTest(product=product, path=path):
                    result = subprocess.run(["bash", "-c", functions + '\ncontent_type "$1"; echo; cache_control "$1"',
                                             "headers", path], capture_output=True, text=True, check=True)
                    self.assertEqual(result.stdout, mime + "\n" + cache)

    def test_product_env_is_scoped_per_job(self):
        data = release_workflow()
        # The two products share one file now, so the differing bucket roots
        # must NOT live at workflow level where they would leak across products.
        self.assertNotIn("PUBLIC_BASE_URL", data["env"])
        self.assertNotIn("R2_PREFIX", data["env"])
        self.assertEqual(data["env"]["R2_BUCKET"], "releases")
        scoped = {
            "server-package": ("https://releases.73zls.com/zeno/server", "zeno/server"),
            "server-publish-r2": ("https://releases.73zls.com/zeno/server", "zeno/server"),
            "computer-package": ("https://releases.73zls.com/zeno", "zeno"),
            "computer-publish-r2": ("https://releases.73zls.com/zeno", "zeno"),
        }
        for job, (base_url, prefix) in scoped.items():
            self.assertEqual(data["jobs"][job]["env"]["PUBLIC_BASE_URL"], base_url, job)
            self.assertEqual(data["jobs"][job]["env"]["R2_PREFIX"], prefix, job)

    def test_artifacts_and_concurrency_are_isolated(self):
        data = release_workflow()
        self.assertNotIn("github.workflow", data["concurrency"]["group"])
        self.assertIn("zeno-release-", data["concurrency"]["group"])

        # The computer artifact is no longer SEA-only (Bun is the published build,
        # SEA the fallback), so its staged artifact carries a neutral name.
        prefixes = {"server": "zeno-server-sea-", "computer": "zeno-computer-bin-"}
        for product in PRODUCTS:
            upload = artifact_step(data, f"{product}-build", "actions/upload-artifact@")
            download = artifact_step(data, f"{product}-package", "actions/download-artifact@")
            prefix = prefixes[product]
            self.assertTrue(upload["with"]["name"].startswith(prefix), product)
            self.assertEqual(download["with"]["pattern"], prefix + "*", product)

        # Server web dist is built once and consumed by every server build leg.
        web_upload = artifact_step(data, "server-web", "actions/upload-artifact@")
        self.assertEqual(web_upload["with"]["name"], "zeno-web-dist")
        web_download = artifact_step(data, "server-build", "actions/download-artifact@")
        self.assertEqual(web_download["with"]["name"], "zeno-web-dist")

        # Release-tree artifact names must not collide between products.
        server_release = artifact_step(data, "server-package", "actions/upload-artifact@")
        computer_release = artifact_step(data, "computer-package", "actions/upload-artifact@")
        self.assertTrue(server_release["with"]["name"].startswith("zeno-server-release-"))
        self.assertTrue(computer_release["with"]["name"].startswith("zeno-release-"))
        self.assertNotEqual(server_release["with"]["name"], computer_release["with"]["name"])

    def test_bytecode_stays_off_the_published_binary(self):
        """The bytecode switch is opt-in and must never reach the published build.

        ZENO_COMPUTER_BYTECODE lives at workflow scope so the variant step can
        read it. The published Bun step therefore has to pin it to "0": otherwise
        a repo variable of 1 makes that step emit a `-bytecode`-named binary, no
        canonical artifact appears, and staging silently falls back to SEA.
        """
        steps = job_steps(release_workflow(), "computer-build")
        published = step_named(steps, "Build Bun binary (published)")
        self.assertEqual(published["env"]["ZENO_COMPUTER_BYTECODE"], "0")
        # No suffix and no --bytecode: the artifact must land on the canonical
        # name that the manifest and the installer key off.
        self.assertNotIn("--bytecode", published["run"])
        self.assertNotIn("--name-suffix", published["run"])

        variant = step_named(steps, "Build Bun bytecode variant")
        self.assertIn("ZENO_COMPUTER_BYTECODE", variant["if"])
        self.assertIn("--bytecode", variant["run"])
        self.assertIn("--name-suffix", variant["run"])

    def test_staging_requires_a_successful_build_not_just_a_file(self):
        """A failed build leg must never be staged as the canonical binary.

        Regression: the linux-x64 Bun build of 0.0.14 failed its own smoke check
        (`--version` answered the Bun runtime version because `strip` had
        destroyed the embedded payload), yet the binary was still on disk, so a
        `-f`-only gate staged it as canonical and the run would have published
        it. Every staging branch therefore has to test the step outcome too.
        """
        steps = job_steps(release_workflow(), "computer-build")
        stage = step_named(steps, "Stage release files")["run"]

        for outcome in ("steps.bun_build.outcome",
                        "steps.sea_build.outcome",
                        "steps.bun_bytecode.outcome"):
            self.assertIn(outcome, stage, outcome)

        # Each `if` that opens a staging branch pairs the outcome with the file.
        for pattern in (
            r'if \[\[ "\$bun_ok" == "success" && -f "\$bun_bin" \]\]',
            r'elif \[\[ "\$sea_ok" == "success" && -f "\$sea_bin" \]\]',
            r'if \[\[ "\$bun_ok" == "success" && "\$bc_ok" == "success"',
        ):
            self.assertRegex(stage, pattern)

        # A bare file-existence gate is the bug itself.
        self.assertNotRegex(stage, r'if \[\[ -f "\$bun_bin" \]\]')
        self.assertNotRegex(stage, r'elif \[\[ -f "\$sea_bin" \]\]')

    def test_bun_legs_are_not_stripped(self):
        """`strip` rewrites the metadata Bun uses to locate its appended payload.

        Stripping a compiled Bun binary corrupted the linux-x64 artifact, so the
        Bun legs must not ask for it. SEA keeps its strip: a Node SEA blob is
        read from the end of the file and survives symbol removal.
        """
        steps = job_steps(release_workflow(), "computer-build")
        for name in ("Build Bun binary (published)", "Build Bun bytecode variant"):
            self.assertNotIn("--strip", step_named(steps, name)["run"], name)
        self.assertIn("--strip", step_named(steps, "Build SEA binary (fallback)")["run"])


class ResolveInputs(unittest.TestCase):
    """The merged workflow resolves everything from workflow_dispatch inputs
    (no repository_dispatch / client_payload), so the normalization + validation
    contract lives entirely in the resolve job's `Resolve inputs` step."""

    def _resolve(self, **inputs):
        import textwrap
        step = step_named(job_steps(release_workflow(), "resolve"), "Resolve inputs")
        script = textwrap.dedent(step["run"])
        # GitHub always injects every declared input as INPUT_* (empty string when
        # unset), so the fixture must too — otherwise `set -u` trips on a key the
        # workflow legitimately leaves unset.
        declared = release_workflow()["on"]["workflow_dispatch"]["inputs"]
        unknown = set(inputs) - set(declared)
        self.assertFalse(unknown, f"undeclared input(s): {sorted(unknown)}")
        input_env = {f"INPUT_{key.upper()}": inputs.get(key, "") for key in declared}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "gh_output"
            output.touch()
            env = {
                **os.environ,
                "GITHUB_OUTPUT": str(output),
                **input_env,
            }
            result = subprocess.run(["bash", "-c", script], env=env,
                                    capture_output=True, text=True)
            values = {}
            for line in output.read_text().splitlines():
                key, _, value = line.partition("=")
                values[key] = value
            return result, values

    def test_defaults_and_derivations(self):
        result, out = self._resolve(source_ref="dev", version="0.0.11")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(out, {
            "source_ref": "dev",
            "version": "0.0.11",
            "release_tag": "computer-v0.0.11",
            "channel": "latest",
            "publish": "true",
            "github_release": "false",
            "retain": "2",
        })

    def test_prerelease_infers_alpha_and_accepts_commit_url(self):
        url = "https://cnb.cool/zls_nmtx/sohaha/bots/-/commit/" + "a" * 40 + "/"
        result, out = self._resolve(source_ref=url, version="0.0.11-rc.3")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(out["source_ref"], "a" * 40)
        self.assertEqual(out["channel"], "alpha")
        self.assertEqual(out["release_tag"], "computer-v0.0.11-rc.3")

    def test_explicit_values_win_and_boolean_coercion(self):
        result, out = self._resolve(
            source_ref="dev", version="0.0.11", release_tag="computer-v0.0.11",
            channel="alpha", publish="false", github_release="true", retain="1",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(out["channel"], "alpha")
        self.assertEqual(out["publish"], "false")
        self.assertEqual(out["github_release"], "true")
        self.assertEqual(out["retain"], "1")

    def test_invalid_values_fail_closed(self):
        cases = {
            "bad version": {"source_ref": "dev", "version": "1.2"},
            "bad channel": {"source_ref": "dev", "version": "0.0.11", "channel": "beta"},
            "bad retain": {"source_ref": "dev", "version": "0.0.11", "retain": "two"},
            "bad release tag": {"source_ref": "dev", "version": "0.0.11", "release_tag": "v0.0.11"},
            "bad source ref": {"source_ref": "bad ref", "version": "0.0.11"},
        }
        for label, inputs in cases.items():
            with self.subTest(case=label):
                result, _ = self._resolve(**inputs)
                self.assertNotEqual(result.returncode, 0, f"{label} should fail")


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
