#!/usr/bin/env node

import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import process from 'node:process'
import { spawn } from 'node:child_process'
import OpenAI from 'openai'
import { DOMParser, XMLSerializer } from '@xmldom/xmldom'

const DEFAULT_PROJECT_PATH = 'LinearMouse.xcodeproj'
const DEFAULT_BASE_URL = 'https://openrouter.ai/api/v1'
const DEFAULT_MODEL = 'openai/gpt-4.1-mini'
const DEFAULT_BATCH_SIZE = 25
const DEFAULT_RETRIES = 3

function printHelp() {
  console.log(`Translate unfinished xcstrings entries through Xcode's XLIFF flow.

Usage:
  npm run translate:xcstrings -- [options]

Options:
  --project <file>        Xcode project path (default: ${DEFAULT_PROJECT_PATH})
  --model <id>            OpenRouter model id (default: ${DEFAULT_MODEL})
  --languages <list>      Comma-separated target languages to export
  --batch-size <number>   Units per model request (default: ${DEFAULT_BATCH_SIZE})
  --max-units <number>    Stop after N unfinished units
  --base-url <url>        API base URL (default: ${DEFAULT_BASE_URL})
  --dry-run               Export and inspect only, do not write back
  --keep-export           Keep the temporary exported .xcloc bundle
  --help                  Show this help

Environment:
  OPENROUTER_API_KEY      Required API key
  OPENROUTER_MODEL        Default model override
  OPENROUTER_BASE_URL     Default base URL override
  OPENROUTER_SITE_URL     Optional HTTP-Referer header
  OPENROUTER_APP_NAME     Optional X-Title header
`)
}

function parseArgs(argv) {
  const options = {
    project: DEFAULT_PROJECT_PATH,
    model: process.env.OPENROUTER_MODEL || DEFAULT_MODEL,
    baseUrl: process.env.OPENROUTER_BASE_URL || DEFAULT_BASE_URL,
    batchSize: DEFAULT_BATCH_SIZE,
    maxUnits: null,
    languages: [],
    dryRun: false,
    keepExport: false,
    help: false,
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]

    if (arg === '--help') {
      options.help = true
      continue
    }

    if (arg === '--dry-run') {
      options.dryRun = true
      continue
    }

    if (arg === '--keep-export') {
      options.keepExport = true
      continue
    }

    if (!arg.startsWith('--')) {
      throw new Error(`Unknown argument: ${arg}`)
    }

    const next = argv[index + 1]
    if (next == null || next.startsWith('--')) {
      throw new Error(`Missing value for ${arg}`)
    }

    switch (arg) {
      case '--project':
        options.project = next
        break
      case '--model':
        options.model = next
        break
      case '--base-url':
        options.baseUrl = next
        break
      case '--batch-size':
        options.batchSize = parsePositiveInteger(next, '--batch-size')
        break
      case '--max-units':
        options.maxUnits = parsePositiveInteger(next, '--max-units')
        break
      case '--languages':
        options.languages = parseList(next)
        break
      default:
        throw new Error(`Unknown argument: ${arg}`)
    }

    index += 1
  }

  return options
}

function parsePositiveInteger(value, flagName) {
  const number = Number.parseInt(value, 10)
  if (!Number.isInteger(number) || number <= 0) {
    throw new Error(`${flagName} must be a positive integer`)
  }
  return number
}

function parseList(value) {
  return value
    .split(',')
    .map(item => item.trim())
    .filter(Boolean)
}

function isObject(value) {
  return value != null && typeof value === 'object' && !Array.isArray(value)
}

async function runCommand(command, args, options = {}) {
  const { cwd = process.cwd() } = options

  await new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      cwd,
      stdio: 'inherit',
      env: process.env,
    })

    child.on('error', reject)
    child.on('exit', code => {
      if (code === 0) {
        resolve()
        return
      }
      reject(new Error(`${command} exited with code ${code}`))
    })
  })
}

function createClient(options) {
  const apiKey = process.env.OPENROUTER_API_KEY
  if (!apiKey) {
    throw new Error('OPENROUTER_API_KEY is required')
  }

  const defaultHeaders = {}
  if (process.env.OPENROUTER_SITE_URL) {
    defaultHeaders['HTTP-Referer'] = process.env.OPENROUTER_SITE_URL
  }
  if (process.env.OPENROUTER_APP_NAME) {
    defaultHeaders['X-Title'] = process.env.OPENROUTER_APP_NAME
  }

  return new OpenAI({
    apiKey,
    baseURL: options.baseUrl,
    defaultHeaders,
  })
}

async function exportLocalizations(projectPath, exportPath, languages) {
  const args = ['-exportLocalizations', '-project', projectPath, '-localizationPath', exportPath]
  for (const language of languages) {
    args.push('-exportLanguage', language)
  }

  console.log('Exporting localizations with xcodebuild...')
  await runCommand('xcodebuild', args)
}

async function importLocalizations(projectPath, xclocPaths) {
  for (const xclocPath of xclocPaths) {
    console.log(`Importing translated localizations from ${path.basename(xclocPath)}...`)
    await runCommand('xcodebuild', [
      '-importLocalizations',
      '-project',
      projectPath,
      '-localizationPath',
      xclocPath,
      '-mergeImport',
    ])
  }
}

async function findExportedXLIFFFiles(exportPath) {
  const entries = await fs.readdir(exportPath, { withFileTypes: true })
  const files = []

  for (const entry of entries) {
    if (!entry.isDirectory() || !entry.name.endsWith('.xcloc')) {
      continue
    }

    const xclocPath = path.join(exportPath, entry.name)
    const contentsPath = path.join(xclocPath, 'contents.json')
    const contents = JSON.parse(await fs.readFile(contentsPath, 'utf8'))
    const localizedDir = path.join(xclocPath, 'Localized Contents')
    const localizedEntries = await fs.readdir(localizedDir, { withFileTypes: true })

    for (const localizedEntry of localizedEntries) {
      if (!localizedEntry.isFile() || !localizedEntry.name.endsWith('.xliff')) {
        continue
      }

      files.push({
        language: contents.targetLocale,
        xclocPath,
        xliffPath: path.join(localizedDir, localizedEntry.name),
      })
    }
  }

  return files.sort((left, right) => left.language.localeCompare(right.language, 'en'))
}

function getFirstChildByTagName(node, tagName) {
  for (let child = node.firstChild; child != null; child = child.nextSibling) {
    if (child.nodeType === child.ELEMENT_NODE && child.tagName === tagName) {
      return child
    }
  }
  return null
}

function shouldKeepUnchanged(source, id) {
  const trimmed = source.trim()
  if (!trimmed) {
    return true
  }

  if (trimmed.includes('%#@')) {
    return true
  }

  if (/^[\d\s.,%()+\-–—:;<>/=\\[\\]{}]*$/.test(trimmed)) {
    return true
  }

  if (/^[^\p{L}]*$/u.test(trimmed)) {
    return true
  }

  if (id === '') {
    return true
  }

  return false
}

function filterDocumentToXCStrings(document) {
  const files = Array.from(document.getElementsByTagName('file'))
  for (const fileNode of files) {
    const original = fileNode.getAttribute('original') || ''
    if (original.endsWith('.xcstrings')) {
      continue
    }
    fileNode.parentNode?.removeChild(fileNode)
  }
}

function collectPendingUnits(document, language) {
  const files = Array.from(document.getElementsByTagName('file'))
  const units = []

  for (const fileNode of files) {
    const original = fileNode.getAttribute('original') || ''
    if (!original.endsWith('.xcstrings')) {
      continue
    }

    const transUnits = Array.from(fileNode.getElementsByTagName('trans-unit'))
    for (const transUnit of transUnits) {
      const id = transUnit.getAttribute('id') || ''
      const sourceNode = getFirstChildByTagName(transUnit, 'source')
      const targetNode = getFirstChildByTagName(transUnit, 'target')
      const noteNode = getFirstChildByTagName(transUnit, 'note')
      const source = sourceNode?.textContent || ''
      const target = targetNode?.textContent || ''
      const state = targetNode?.getAttribute('state') || ''

      if (source.trim().length === 0) {
        continue
      }

      if (state === 'translated' && target.length > 0) {
        continue
      }

      units.push({
        id,
        language,
        source,
        note: noteNode?.textContent || '',
        targetNode,
        transUnit,
      })
    }
  }

  return units
}

function buildMessages(language, batch) {
  const system = [
    'You translate Apple XLIFF units for a macOS utility app.',
    'Return JSON only. Do not wrap it in Markdown.',
    'Preserve placeholders and special tokens exactly, including %@, %1$@, %d, %lld, %.1f, %#@value@, %% and escaped newlines.',
    'Keep ids unchanged.',
    'Use concise, natural product UI wording.',
    'If a string should remain identical in the target language, return it unchanged.',
    'Output format: {"items":[{"id":"...","target":"..."}]}.',
  ].join(' ')

  const user = {
    targetLanguage: language,
    items: batch.map(item => ({
      id: item.id,
      source: item.source,
      note: item.note,
    })),
  }

  return [
    { role: 'system', content: system },
    { role: 'user', content: JSON.stringify(user) },
  ]
}

function extractJson(text) {
  const trimmed = text.trim()
  if (!trimmed) {
    throw new Error('Model returned an empty response')
  }

  try {
    return JSON.parse(trimmed)
  } catch {}

  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i)
  if (fenced) {
    return JSON.parse(fenced[1])
  }

  const start = trimmed.indexOf('{')
  const end = trimmed.lastIndexOf('}')
  if (start >= 0 && end > start) {
    return JSON.parse(trimmed.slice(start, end + 1))
  }

  throw new Error('Unable to parse JSON from model response')
}

function validateBatchResponse(batch, response) {
  if (!isObject(response) || !Array.isArray(response.items)) {
    throw new Error('Model response must include an items array')
  }

  const translatedById = new Map(response.items.map(item => [item.id, item]))
  for (const item of batch) {
    const translated = translatedById.get(item.id)
    if (!translated || typeof translated.target !== 'string') {
      throw new Error(`Missing translation for unit: ${item.id}`)
    }
  }

  return translatedById
}

async function translateBatch(client, language, batch, options, attempt = 1) {
  try {
    const completion = await client.chat.completions.create({
      model: options.model,
      temperature: 0.2,
      messages: buildMessages(language, batch),
    })

    const content = completion.choices[0]?.message?.content || ''
    const response = extractJson(content)
    return validateBatchResponse(batch, response)
  } catch (error) {
    if (attempt >= DEFAULT_RETRIES) {
      throw error
    }

    const delayMs = 1000 * 2 ** (attempt - 1)
    console.warn(`Retrying ${language} batch after error: ${error.message}`)
    await new Promise(resolve => setTimeout(resolve, delayMs))
    return translateBatch(client, language, batch, options, attempt + 1)
  }
}

function createTargetNode(document, transUnit) {
  const targetNode = document.createElement('target')
  const noteNode = getFirstChildByTagName(transUnit, 'note')

  if (noteNode) {
    transUnit.insertBefore(targetNode, noteNode)
  } else {
    transUnit.appendChild(targetNode)
  }

  return targetNode
}

function chunk(items, size) {
  const chunks = []
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size))
  }
  return chunks
}

async function processXLIFFFile(fileInfo, client, options, remainingBudget) {
  const xml = await fs.readFile(fileInfo.xliffPath, 'utf8')
  const document = new DOMParser().parseFromString(xml, 'application/xml')
  filterDocumentToXCStrings(document)
  let units = collectPendingUnits(document, fileInfo.language)

  if (remainingBudget != null) {
    units = units.slice(0, remainingBudget)
  }

  if (units.length === 0) {
    return { language: fileInfo.language, translatedCount: 0, scannedCount: 0 }
  }

  console.log(`Found ${units.length} unfinished units for ${fileInfo.language}.`)

  if (options.dryRun) {
    return { language: fileInfo.language, translatedCount: 0, scannedCount: units.length }
  }

  let translatedCount = 0
  const modelUnits = []

  for (const unit of units) {
    if (!shouldKeepUnchanged(unit.source, unit.id)) {
      modelUnits.push(unit)
      continue
    }

    const targetNode = unit.targetNode || createTargetNode(document, unit.transUnit)
    targetNode.setAttribute('state', 'translated')
    targetNode.textContent = unit.source
    translatedCount += 1
  }

  const batches = chunk(modelUnits, options.batchSize)

  for (const [index, batch] of batches.entries()) {
    console.log(`Translating ${fileInfo.language} batch ${index + 1}/${batches.length}...`)
    const translations = await translateBatch(client, fileInfo.language, batch, options)

    for (const unit of batch) {
      const translated = translations.get(unit.id)
      const targetNode = unit.targetNode || createTargetNode(document, unit.transUnit)
      targetNode.setAttribute('state', 'translated')
      targetNode.textContent = translated.target
      translatedCount += 1
    }
  }

  const output = new XMLSerializer().serializeToString(document)
  await fs.writeFile(fileInfo.xliffPath, `${output}\n`)

  return { language: fileInfo.language, translatedCount, scannedCount: units.length }
}

async function removeDirectoryIfNeeded(targetPath, keep) {
  if (keep) {
    console.log(`Kept exported localizations at ${targetPath}`)
    return
  }

  await fs.rm(targetPath, { recursive: true, force: true })
}

async function main() {
  const options = parseArgs(process.argv.slice(2))
  if (options.help) {
    printHelp()
    return
  }

  const projectPath = path.resolve(process.cwd(), options.project)
  const exportPath = await fs.mkdtemp(path.join(os.tmpdir(), 'linearmouse-xcloc-'))
  const shouldKeepExport = options.keepExport || options.dryRun

  try {
    await exportLocalizations(projectPath, exportPath, options.languages)
    const exportedFiles = await findExportedXLIFFFiles(exportPath)

    if (exportedFiles.length === 0) {
      console.log('No exported XLIFF files found.')
      return
    }

    let remainingBudget = options.maxUnits
    let totalPendingUnits = 0
    let totalTranslatedUnits = 0
    const perLanguage = []
    const client = options.dryRun ? null : createClient(options)

    for (const fileInfo of exportedFiles) {
      if (remainingBudget === 0) {
        break
      }

      const result = await processXLIFFFile(fileInfo, client, options, remainingBudget)
      totalPendingUnits += result.scannedCount
      totalTranslatedUnits += result.translatedCount
      perLanguage.push(result)

      if (remainingBudget != null) {
        remainingBudget -= result.scannedCount
      }
    }

    if (totalPendingUnits === 0) {
      console.log('No unfinished xcstrings translations found.')
      return
    }

    for (const result of perLanguage) {
      if (result.scannedCount === 0) {
        continue
      }

      if (options.dryRun) {
        console.log(`${result.language}: ${result.scannedCount} unfinished units`)
      } else {
        console.log(`${result.language}: translated ${result.translatedCount} units`)
      }
    }

    if (options.dryRun) {
      console.log(`Dry run complete. Found ${totalPendingUnits} unfinished units.`)
      return
    }

    if (totalTranslatedUnits === 0) {
      console.log('Nothing was translated.')
      return
    }

    const xclocPaths = [...new Set(exportedFiles.map(file => file.xclocPath))]
    await importLocalizations(projectPath, xclocPaths)
    console.log(`Imported ${totalTranslatedUnits} translated units into the project.`)
  } finally {
    await removeDirectoryIfNeeded(exportPath, shouldKeepExport)
  }
}

main().catch(error => {
  console.error(error.message)
  process.exitCode = 1
})
