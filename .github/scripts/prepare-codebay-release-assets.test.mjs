import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import {
	parseUpdateManifest,
	prepareReleaseAssets,
} from "./prepare-codebay-release-assets.mjs";

function createTempDir() {
	return mkdtempSync(path.join(tmpdir(), "codebay-release-assets-"));
}

function writeFile(filePath, content) {
	mkdirSync(path.dirname(filePath), { recursive: true });
	writeFileSync(filePath, content);
}

test("prepareReleaseAssets merges mac manifests from current artifacts", () => {
	const rootDir = createTempDir();
	const outputDir = path.join(rootDir, "out");

	try {
		writeFile(path.join(rootDir, "release-mac-arm64", "Codebay-1.2.3-arm64.dmg"), "arm64-dmg");
		writeFile(
			path.join(rootDir, "release-mac-arm64", "Codebay-1.2.3-arm64-mac.zip"),
			"arm64-zip",
		);
		writeFile(
			path.join(rootDir, "release-mac-arm64", "latest-mac.yml"),
			[
				"version: 1.2.3",
				"files:",
				"  - url: Codebay-1.2.3-arm64-mac.zip",
				"    sha512: arm64zip",
				"    size: 111",
				"  - url: Codebay-1.2.3-arm64.dmg",
				"    sha512: arm64dmg",
				"    size: 222",
				"path: Codebay-1.2.3-arm64-mac.zip",
				"sha512: arm64zip",
				"releaseDate: '2026-03-24T11:17:00.000Z'",
				"",
			].join("\n"),
		);
		writeFile(
			path.join(rootDir, "release-mac-arm64", "builder-debug.yml"),
			"debug-arm64\n",
		);

		writeFile(path.join(rootDir, "release-mac-x64", "Codebay-1.2.3.dmg"), "x64-dmg");
		writeFile(path.join(rootDir, "release-mac-x64", "Codebay-1.2.3-mac.zip"), "x64-zip");
		writeFile(
			path.join(rootDir, "release-mac-x64", "latest-mac.yml"),
			[
				"version: 1.2.3",
				"files:",
				"  - url: Codebay-1.2.3-mac.zip",
				"    sha512: x64zip",
				"    size: 333",
				"  - url: Codebay-1.2.3.dmg",
				"    sha512: x64dmg",
				"    size: 444",
				"path: Codebay-1.2.3-mac.zip",
				"sha512: x64zip",
				"releaseDate: '2026-03-24T11:19:00.000Z'",
				"",
			].join("\n"),
		);
		writeFile(path.join(rootDir, "release-mac-x64", "app-update.yml"), "owner: sohaha\n");
		writeFile(
			path.join(rootDir, "release-mac-x64", "builder-debug.yml"),
			"debug-x64\n",
		);

		writeFile(path.join(rootDir, "release-win-x64", "Codebay-1.2.3-x64.exe"), "win-exe");
		writeFile(
			path.join(rootDir, "release-win-x64", "latest.yml"),
			[
				"version: 1.2.3",
				"files:",
				"  - url: Codebay-1.2.3-x64.exe",
				"    sha512: winexe",
				"    size: 555",
				"path: Codebay-1.2.3-x64.exe",
				"sha512: winexe",
				"releaseDate: '2026-03-24T11:21:00.000Z'",
				"",
			].join("\n"),
		);

		const result = prepareReleaseAssets({
			artifactsRoot: rootDir,
			outputDir,
		});

		assert.ok(result.files.includes("latest-mac.yml"));
		assert.ok(result.files.includes("latest-mac-arm64.yml"));
		assert.ok(result.files.includes("latest-mac-x64.yml"));
		assert.ok(result.files.includes("builder-debug-mac-arm64.yml"));
		assert.ok(result.files.includes("builder-debug-mac-x64.yml"));
		assert.ok(result.files.includes("latest.yml"));

		const mergedManifest = parseUpdateManifest(
			readFileSync(path.join(outputDir, "latest-mac.yml"), "utf8"),
		);

		assert.equal(mergedManifest.path, "Codebay-1.2.3-mac.zip");
		assert.equal(mergedManifest.sha512, "x64zip");
		assert.deepEqual(
			mergedManifest.files.map((file) => file.url),
			[
				"Codebay-1.2.3-mac.zip",
				"Codebay-1.2.3.dmg",
				"Codebay-1.2.3-arm64-mac.zip",
				"Codebay-1.2.3-arm64.dmg",
			],
		);
	} finally {
		rmSync(rootDir, { force: true, recursive: true });
	}
});

test("prepareReleaseAssets preserves missing mac arch from existing manifests", () => {
	const rootDir = createTempDir();
	const existingDir = path.join(rootDir, "existing");
	const outputDir = path.join(rootDir, "out");

	try {
		writeFile(path.join(rootDir, "release-mac-arm64", "Codebay-1.2.3-arm64.dmg"), "arm64-dmg");
		writeFile(
			path.join(rootDir, "release-mac-arm64", "Codebay-1.2.3-arm64-mac.zip"),
			"arm64-zip",
		);
		writeFile(
			path.join(rootDir, "release-mac-arm64", "latest-mac.yml"),
			[
				"version: 1.2.3",
				"files:",
				"  - url: Codebay-1.2.3-arm64-mac.zip",
				"    sha512: arm64zip-new",
				"    size: 111",
				"  - url: Codebay-1.2.3-arm64.dmg",
				"    sha512: arm64dmg-new",
				"    size: 222",
				"path: Codebay-1.2.3-arm64-mac.zip",
				"sha512: arm64zip-new",
				"releaseDate: '2026-03-24T12:00:00.000Z'",
				"",
			].join("\n"),
		);
		writeFile(
			path.join(existingDir, "latest-mac-x64.yml"),
			[
				"version: 1.2.3",
				"files:",
				"  - url: Codebay-1.2.3-mac.zip",
				"    sha512: x64zip-old",
				"    size: 333",
				"  - url: Codebay-1.2.3.dmg",
				"    sha512: x64dmg-old",
				"    size: 444",
				"path: Codebay-1.2.3-mac.zip",
				"sha512: x64zip-old",
				"releaseDate: '2026-03-24T11:19:00.000Z'",
				"",
			].join("\n"),
		);

		prepareReleaseAssets({
			artifactsRoot: rootDir,
			outputDir,
			existingDir,
		});

		const mergedManifest = parseUpdateManifest(
			readFileSync(path.join(outputDir, "latest-mac.yml"), "utf8"),
		);
		assert.deepEqual(
			mergedManifest.files.map((file) => file.url),
			[
				"Codebay-1.2.3-mac.zip",
				"Codebay-1.2.3.dmg",
				"Codebay-1.2.3-arm64-mac.zip",
				"Codebay-1.2.3-arm64.dmg",
			],
		);
		assert.equal(mergedManifest.path, "Codebay-1.2.3-mac.zip");
		assert.equal(mergedManifest.sha512, "x64zip-old");
	} finally {
		rmSync(rootDir, { force: true, recursive: true });
	}
});

test("prepareReleaseAssets fails on conflicting duplicate assets", () => {
	const rootDir = createTempDir();
	const outputDir = path.join(rootDir, "out");

	try {
		writeFile(path.join(rootDir, "release-mac-arm64", "Codebay-1.2.3-arm64.dmg"), "first");
		writeFile(path.join(rootDir, "release-mac-x64", "Codebay-1.2.3-arm64.dmg"), "second");

		assert.throws(
			() =>
				prepareReleaseAssets({
					artifactsRoot: rootDir,
					outputDir,
				}),
			/conflicting asset detected/i,
		);
	} finally {
		rmSync(rootDir, { force: true, recursive: true });
	}
});
