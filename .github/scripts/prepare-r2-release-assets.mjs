import { createHash } from 'node:crypto'
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import path from 'node:path'

const EXPECTED_TARGETS = new Set([
  'aarch64-apple-darwin',
  'x86_64-apple-darwin',
  'aarch64-pc-windows-msvc',
  'x86_64-pc-windows-msvc',
  'aarch64-unknown-linux-gnu',
  'x86_64-unknown-linux-gnu',
])

function usage() {
  console.error('usage: node prepare-r2-release-assets.mjs <artifacts-dir> <output-dir> <version> <public-base-url>')
  process.exit(1)
}

function sha256(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex')
}

function collectZipFiles(rootDir) {
  return readdirSync(rootDir)
    .map((name) => path.join(rootDir, name))
    .filter((entryPath) => statSync(entryPath).isFile() && entryPath.endsWith('.zip'))
    .sort()
}

const [, , artifactsDir, outputDir, version, publicBaseUrlArg] = process.argv
if (!artifactsDir || !outputDir || !version || !publicBaseUrlArg) usage()

const publicBaseUrl = publicBaseUrlArg.replace(/\/+$/, '')
const releaseNotesUrl = `${publicBaseUrl}/#v${version}`
const expectedPrefix = `ZKey-v${version}-`
const zipFiles = collectZipFiles(artifactsDir)

if (zipFiles.length < EXPECTED_TARGETS.size) {
  throw new Error(`expected at least ${EXPECTED_TARGETS.size} release ZIPs, found ${zipFiles.length}`)
}

rmSync(outputDir, { force: true, recursive: true })
mkdirSync(outputDir, { recursive: true })

const seenTargets = new Set()
const assets = zipFiles.map((filePath) => {
  const fileName = path.basename(filePath)
  if (!fileName.startsWith(expectedPrefix)) {
    throw new Error(`unexpected asset name for ${version}: ${fileName}`)
  }

  const target = fileName.slice(expectedPrefix.length, -'.zip'.length)
  if (!EXPECTED_TARGETS.has(target)) {
    throw new Error(`unexpected target in asset name: ${fileName}`)
  }
  if (seenTargets.has(target)) {
    throw new Error(`duplicate target asset: ${target}`)
  }
  seenTargets.add(target)

  const destinationPath = path.join(outputDir, fileName)
  copyFileSync(filePath, destinationPath)
  const size = statSync(destinationPath).size

  return {
    target,
    name: fileName,
    size,
    sha256: sha256(destinationPath),
  }
})

for (const target of EXPECTED_TARGETS) {
  if (!seenTargets.has(target)) {
    throw new Error(`missing asset for target ${target}`)
  }
}

const manifest = {
  version,
  publishedAt: new Date().toISOString(),
  releaseNotesUrl,
  assets: assets
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((asset) => ({
      ...asset,
      url: `${publicBaseUrl}/${asset.name}`,
    })),
}

writeFileSync(path.join(outputDir, 'latest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
