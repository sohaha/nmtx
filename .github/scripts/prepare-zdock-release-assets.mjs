import { createHash } from 'node:crypto'
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import path from 'node:path'

// Stable asset names produced by .github/workflows/zdock.yml. Each platform has
// a bundled build (ships its own Node runtime) and a system build (reuses the
// machine's Node 24+ runtime).
const SUFFIX_TO_PLATFORM = new Map([
  ['macos-arm64.dmg', 'macos-arm64'],
  ['macos-x64.dmg', 'macos-x64'],
  ['windows-x64-setup.exe', 'windows-x64'],
  ['linux-x64.AppImage', 'linux-x64-appimage'],
  ['linux-x64.deb', 'linux-x64-deb'],
])

function usage() {
  console.error('usage: node prepare-zdock-release-assets.mjs <artifacts-dir> <output-dir> <version> <public-base-url>')
  process.exit(1)
}

function sha256(filePath) {
  return createHash('sha256').update(readFileSync(filePath)).digest('hex')
}

function collectFiles(rootDir) {
  return readdirSync(rootDir)
    .map((name) => path.join(rootDir, name))
    .filter((entryPath) => statSync(entryPath).isFile())
    .sort()
}

function describeAsset(fileName, version) {
  const mode = fileName.startsWith('Zdock-System-v') ? 'system' : 'bundled'
  const prefix = mode === 'system' ? `Zdock-System-v${version}-` : `Zdock-v${version}-`
  if (!fileName.startsWith(prefix)) {
    throw new Error(`unexpected asset name for version ${version}: ${fileName}`)
  }
  const suffix = fileName.slice(prefix.length)
  const platform = SUFFIX_TO_PLATFORM.get(suffix)
  if (!platform) {
    throw new Error(`unexpected asset suffix: ${fileName}`)
  }
  return { mode, platform }
}

const [, , artifactsDir, outputDir, version, publicBaseUrlArg] = process.argv
if (!artifactsDir || !outputDir || !version || !publicBaseUrlArg) usage()

const publicBaseUrl = publicBaseUrlArg.replace(/\/+$/, '')
const releaseNotesUrl = `${publicBaseUrl}/#v${version}`

// Expected set: every platform suffix in both bundled and system mode.
const expectedNames = new Set()
for (const suffix of SUFFIX_TO_PLATFORM.keys()) {
  expectedNames.add(`Zdock-v${version}-${suffix}`)
  expectedNames.add(`Zdock-System-v${version}-${suffix}`)
}

const files = collectFiles(artifactsDir)
const seenNames = new Set()

rmSync(outputDir, { force: true, recursive: true })
mkdirSync(outputDir, { recursive: true })

const assets = files.map((filePath) => {
  const fileName = path.basename(filePath)
  if (seenNames.has(fileName)) {
    throw new Error(`duplicate asset: ${fileName}`)
  }
  seenNames.add(fileName)

  const { mode, platform } = describeAsset(fileName, version)
  const destinationPath = path.join(outputDir, fileName)
  copyFileSync(filePath, destinationPath)

  return {
    mode,
    platform,
    name: fileName,
    size: statSync(destinationPath).size,
    sha256: sha256(destinationPath),
  }
})

const missing = [...expectedNames].filter((name) => !seenNames.has(name))
if (missing.length > 0) {
  throw new Error(`missing release assets:\n  ${missing.join('\n  ')}`)
}

const unexpected = [...seenNames].filter((name) => !expectedNames.has(name))
if (unexpected.length > 0) {
  throw new Error(`unexpected release assets:\n  ${unexpected.join('\n  ')}`)
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
