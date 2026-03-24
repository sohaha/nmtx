import { copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import path from "node:path";
import { fileURLToPath } from "node:url";

function normalizeNewlines(value) {
	return value.replace(/\r\n/g, "\n");
}

function unquote(value) {
	const trimmed = value.trim();
	if (
		(trimmed.startsWith("'") && trimmed.endsWith("'")) ||
		(trimmed.startsWith('"') && trimmed.endsWith('"'))
	) {
		return trimmed.slice(1, -1);
	}
	return trimmed;
}

function parseScalar(value) {
	const normalized = unquote(value);
	if (/^-?\d+$/.test(normalized)) {
		return Number(normalized);
	}
	return normalized;
}

export function parseUpdateManifest(content) {
	const manifest = {
		files: [],
	};
	let currentFile = null;
	let inFiles = false;

	for (const rawLine of normalizeNewlines(content).split("\n")) {
		const line = rawLine.replace(/\s+$/, "");
		if (line.trim() === "") {
			continue;
		}

		if (line === "files:") {
			inFiles = true;
			currentFile = null;
			continue;
		}

		const fileStartMatch = line.match(/^  - ([A-Za-z0-9_]+):\s*(.+)$/);
		if (inFiles && fileStartMatch) {
			currentFile = {
				[fileStartMatch[1]]: parseScalar(fileStartMatch[2]),
			};
			manifest.files.push(currentFile);
			continue;
		}

		const fileFieldMatch = line.match(/^    ([A-Za-z0-9_]+):\s*(.+)$/);
		if (inFiles && currentFile && fileFieldMatch) {
			currentFile[fileFieldMatch[1]] = parseScalar(fileFieldMatch[2]);
			continue;
		}

		inFiles = false;
		currentFile = null;

		const topLevelMatch = line.match(/^([A-Za-z0-9_]+):\s*(.+)$/);
		if (topLevelMatch) {
			manifest[topLevelMatch[1]] = parseScalar(topLevelMatch[2]);
		}
	}

	return manifest;
}

function formatScalar(key, value) {
	if (typeof value === "number") {
		return String(value);
	}
	if (key === "releaseDate") {
		return `'${String(value).replace(/'/g, "''")}'`;
	}
	return String(value);
}

export function dumpUpdateManifest(manifest) {
	const lines = [];

	if (manifest.version != null) {
		lines.push(`version: ${formatScalar("version", manifest.version)}`);
	}

	lines.push("files:");
	for (const file of manifest.files ?? []) {
		lines.push(`  - url: ${formatScalar("url", file.url)}`);
		for (const key of ["sha512", "size", "blockMapSize"]) {
			if (file[key] != null) {
				lines.push(`    ${key}: ${formatScalar(key, file[key])}`);
			}
		}
	}

	for (const key of ["path", "sha512", "releaseDate"]) {
		if (manifest[key] != null) {
			lines.push(`${key}: ${formatScalar(key, manifest[key])}`);
		}
	}

	return `${lines.join("\n")}\n`;
}

function hashFile(filePath) {
	return createHash("sha256").update(readFileSync(filePath)).digest("hex");
}

function ensureDirectory(dirPath) {
	mkdirSync(dirPath, { recursive: true });
}

function copySingleton({ sourcePath, destinationPath }) {
	if (!existsSync(destinationPath)) {
		copyFileSync(sourcePath, destinationPath);
		return;
	}

	if (hashFile(sourcePath) !== hashFile(destinationPath)) {
		throw new Error(`Conflicting singleton asset detected: ${path.basename(destinationPath)}`);
	}
}

function copyUniqueAsset({ sourcePath, destinationPath }) {
	if (!existsSync(destinationPath)) {
		copyFileSync(sourcePath, destinationPath);
		return;
	}

	if (hashFile(sourcePath) !== hashFile(destinationPath)) {
		throw new Error(
			`Conflicting asset detected for ${path.basename(destinationPath)} from ${sourcePath}`,
		);
	}
}

function mergeManifestPair({ baseManifest, nextManifest }) {
	const mergedFiles = [...(baseManifest.files ?? []).map((file) => ({ ...file }))];
	const indexByUrl = new Map(mergedFiles.map((file, index) => [file.url, index]));

	for (const candidate of nextManifest.files ?? []) {
		const existingIndex = indexByUrl.get(candidate.url);
		if (existingIndex == null) {
			indexByUrl.set(candidate.url, mergedFiles.length);
			mergedFiles.push({ ...candidate });
			continue;
		}

		mergedFiles[existingIndex] = {
			...mergedFiles[existingIndex],
			...candidate,
		};
	}

	const releaseDates = [baseManifest.releaseDate, nextManifest.releaseDate].filter(Boolean);
	let releaseDate = baseManifest.releaseDate;
	if (releaseDates.length > 0) {
		releaseDate = releaseDates.sort().at(-1);
	}

	return {
		...baseManifest,
		files: mergedFiles,
		releaseDate,
	};
}

function listTargetDirectories(rootDir) {
	if (!existsSync(rootDir)) {
		return [];
	}

	return readdirSync(rootDir)
		.filter((name) => name.startsWith("release-"))
		.map((name) => path.join(rootDir, name))
		.filter((entryPath) => statSync(entryPath).isDirectory());
}

function readArtifactFiles(targetDir) {
	return readdirSync(targetDir)
		.map((name) => path.join(targetDir, name))
		.filter((entryPath) => statSync(entryPath).isFile());
}

function collectExistingMacManifests(existingDir) {
	const manifests = new Map();
	if (!existingDir || !existsSync(existingDir)) {
		return manifests;
	}

	for (const entryPath of readdirSync(existingDir).map((name) => path.join(existingDir, name))) {
		if (!statSync(entryPath).isFile()) {
			continue;
		}

		const match = path.basename(entryPath).match(/^latest-mac-(arm64|x64)\.yml$/);
		if (!match) {
			continue;
		}

		manifests.set(match[1], parseUpdateManifest(readFileSync(entryPath, "utf8")));
	}

	return manifests;
}

export function prepareReleaseAssets({
	artifactsRoot,
	outputDir,
	existingDir,
}) {
	rmSync(outputDir, { force: true, recursive: true });
	ensureDirectory(outputDir);

	const macManifests = collectExistingMacManifests(existingDir);
	const latestManifests = new Map();

	for (const targetDir of listTargetDirectories(artifactsRoot)) {
		const targetDirName = path.basename(targetDir);
		const target = targetDirName.replace(/^release-/, "");
		const macTargetMatch = target.match(/^mac-(arm64|x64)$/);

		for (const filePath of readArtifactFiles(targetDir)) {
			const fileName = path.basename(filePath);

			if (fileName === "latest-mac.yml") {
				if (!macTargetMatch) {
					throw new Error(`latest-mac.yml uploaded from unexpected target: ${target}`);
				}

				macManifests.set(macTargetMatch[1], parseUpdateManifest(readFileSync(filePath, "utf8")));
				continue;
			}

			if (fileName === "latest.yml") {
				latestManifests.set(target, readFileSync(filePath, "utf8"));
				continue;
			}

			if (fileName === "builder-debug.yml") {
				copyUniqueAsset({
					sourcePath: filePath,
					destinationPath: path.join(outputDir, `builder-debug-${target}.yml`),
				});
				continue;
			}

			if (fileName === "app-update.yml") {
				copySingleton({
					sourcePath: filePath,
					destinationPath: path.join(outputDir, fileName),
				});
				continue;
			}

			copyUniqueAsset({
				sourcePath: filePath,
				destinationPath: path.join(outputDir, fileName),
			});
		}
	}

	if (latestManifests.size > 0) {
		const preferredTarget = latestManifests.has("win-x64")
			? "win-x64"
			: [...latestManifests.keys()].sort()[0];
		writeFileSync(path.join(outputDir, "latest.yml"), latestManifests.get(preferredTarget));
	}

	if (macManifests.size > 0) {
		for (const [arch, manifest] of macManifests) {
			writeFileSync(
				path.join(outputDir, `latest-mac-${arch}.yml`),
				dumpUpdateManifest(manifest),
			);
		}

		const orderedArchs = ["x64", "arm64"].filter((arch) => macManifests.has(arch));
		let mergedManifest = macManifests.get(orderedArchs[0]);
		for (const arch of orderedArchs.slice(1)) {
			mergedManifest = mergeManifestPair({
				baseManifest: mergedManifest,
				nextManifest: macManifests.get(arch),
			});
		}

		writeFileSync(path.join(outputDir, "latest-mac.yml"), dumpUpdateManifest(mergedManifest));
	}

	return {
		files: readdirSync(outputDir).sort(),
	};
}

const isCliInvocation =
	process.argv[1] != null &&
	fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);

if (isCliInvocation) {
	const artifactsRoot = process.argv[2];
	const outputDir = process.argv[3];
	const existingDir = process.argv[4];

	if (!artifactsRoot || !outputDir) {
		console.error(
			"usage: node prepare-codebay-release-assets.mjs <artifacts-root> <output-dir> [existing-dir]",
		);
		process.exit(1);
	}

	const result = prepareReleaseAssets({
		artifactsRoot: path.resolve(artifactsRoot),
		outputDir: path.resolve(outputDir),
		existingDir: existingDir ? path.resolve(existingDir) : undefined,
	});

	for (const fileName of result.files) {
		console.log(fileName);
	}
}
