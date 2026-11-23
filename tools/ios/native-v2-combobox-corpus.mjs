#!/usr/bin/env node
/** 使用前端锁定的真实 Vuetify 模块生成独立值语义语料，不运行插件或访问服务。 */
import { readFile, writeFile } from 'node:fs/promises'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const root = resolve(process.argv[2] ?? '')
const output = process.argv[3]
if (!output) throw new Error('Usage: node native-v2-combobox-corpus.mjs <Frontend> <output>')
const packageRoot = resolve(root, 'node_modules/vuetify')
const version = JSON.parse(await readFile(resolve(packageRoot, 'package.json'), 'utf8')).version
if (version !== '3.7.3') throw new Error(`Expected Vuetify 3.7.3, found ${version}`)
const { useItems, transformItem } = await import(pathToFileURL(resolve(packageRoot, 'lib/composables/list-items.mjs')).href)
const { deepEqual, wrapInArray } = await import(pathToFileURL(resolve(packageRoot, 'lib/util/helpers.mjs')).href)

/** 仅统一 JSON 属性的 Vuetify 别名；原始配置仍留在语料供 Swift 计划器读取。 */
function normalized(properties) {
  const aliases = { 'return-object': 'returnObject', 'item-title': 'itemTitle', 'item-value': 'itemValue' }
  return {
    items: [], itemTitle: 'title', itemValue: 'value', itemChildren: 'children', itemProps: 'props',
    returnObject: true, multiple: false, clearable: false, valueComparator: deepEqual,
    ...Object.fromEntries(Object.entries(properties).map(([key, value]) => [aliases[key] ?? key, value])),
  }
}

/** 状态操作依据 VCombobox 3.7.3 select / transformOut，投影直接调用该包而非复制 Swift。 */
function reference(properties, current, operations) {
  const props = normalized(properties)
  const { items, transformIn, transformOut } = useItems(props)
  let selected = transformIn(wrapInArray(current))
  const initialTitles = selected.map(item => item.title)
  let edited = false
  for (const op of operations) {
    if (op.kind === 'clear') {
      if (props.clearable) { selected = []; edited = true }
      continue
    }
    if (op.kind === 'remove') {
      if (selected[op.index] && !selected[op.index].props.disabled) { selected.splice(op.index, 1); edited = true }
      continue
    }
    const item = op.kind === 'custom' ? transformItem(props, op.text) : items.value[op.index]
    if (!item || item.props.disabled || (op.kind === 'custom' && !op.text)) continue
    if (props.multiple) {
      const index = selected.findIndex(value => props.valueComparator(value.value, item.value))
      const add = op.kind === 'custom' || index < 0
      if (index >= 0) selected.splice(index, 1)
      if (add) selected.push(item)
    } else selected = [item]
    edited = true
  }
  const transformed = transformOut(selected)
  const value = edited ? (props.multiple ? transformed : transformed[0] ?? null) : current
  return { initialTitles, finalTitles: selected.map(item => item.title),
    changed: !deepEqual(current, value), ...(value === undefined ? {} : { expected: value }) }
}

const inputs = [undefined, null, 'v', ['v', 'old'], { title: '历史对象', value: 'old', future: 42 }, [null, 'v', 'é', 'e\u0301']]
const optionSets = [[], ['v', 1, '1', null], [{ title: '预设', value: 'v' }, { title: '停用', value: 'locked', props: { disabled: true } }]]
const operations = [[], [{ kind: 'choose', index: 0 }], [{ kind: 'custom', text: 'v' }],
  [{ kind: 'custom', text: ' custom ' }, { kind: 'custom', text: 'v' }, { kind: 'remove', index: 0 }], [{ kind: 'clear' }]]
const cases = []
for (const multiple of [false, true]) for (const returnsObject of [false, true]) {
  for (const items of optionSets) for (const current of inputs) for (const ops of operations) {
    const properties = { multiple, 'return-object': returnsObject, clearable: true, items }
    cases.push({ properties, ...(current === undefined ? {} : { current }), operations: ops, ...reference(properties, current, ops) })
  }
}
for (const [title, value] of [['meta.title', 'meta.ids[0]'], [['meta', 'title'], ['meta', 'ids', 0]], [true, true], [false, false], [[], []]]) {
  const properties = { 'item-title': title, 'item-value': value, 'return-object': false,
    items: [{ 'meta.title': '完整键', meta: { title: '嵌套', ids: [42] } }] }
  const ops = [{ kind: 'choose', index: 0 }]
  cases.push({ properties, current: null, operations: ops, ...reference(properties, null, ops) })
}
await writeFile(output, '{\n  "reference": "Vuetify list-items / helpers, VCombobox select 3.7.3",\n'
  + `  "version": ${JSON.stringify(version)},\n  "cases": [\n`
  + cases.map(entry => '    ' + JSON.stringify(entry)).join(',\n') + '\n  ]\n}\n')
process.stdout.write(`Generated ${cases.length} independent cases using Vuetify ${version}\n`)
