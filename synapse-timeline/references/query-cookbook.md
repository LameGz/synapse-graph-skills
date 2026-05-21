# Query Cookbook

Common query patterns for `query_timeline.sh`.

## Daily Workflow

**"今天做了啥？"**
```bash
bash scripts/query_timeline.sh --project . --recent 1 --summary
```

**"这周做了什么？"**
```bash
bash scripts/query_timeline.sh --project . --recent 7 --summary --limit 30
```

**"昨天改了哪些模块？"**
```bash
bash scripts/query_timeline.sh --project . --recent 1 --summary
# Look at the tags: line to see which modules
```

## Module-Specific

**"登录功能最近改了什么？"**
```bash
bash scripts/query_timeline.sh --project . --tag login --recent 14
```

**"支付模块的所有历史记录"**
```bash
bash scripts/query_timeline.sh --project . --tag payment --limit 50
```

**"某个具体节点上次改了啥？"**
```bash
bash scripts/query_timeline.sh --project . --node meta/feat_login.md --limit 5
```

## Progress & Issues

**"还有哪些没做完？"**
```bash
bash scripts/query_timeline.sh --project . --issues
```

**"auth 相关的待办"**
```bash
bash scripts/query_timeline.sh --project . --tag auth --issues
```

**"整体进度快照"**
```bash
bash scripts/query_timeline.sh --project . --issues --summary
```

## Date Range

**"上个月改了啥？"**
```bash
bash scripts/query_timeline.sh --project . --since 2026-04-01 --limit 50
```

**"某个日期区间的改动"**
```bash
bash scripts/query_timeline.sh --project . --since 2026-05-01 --limit 30
# --since handles the lower bound; entries before this date are excluded
```

## Troubleshooting

**"No matching entries"**
- Run `generate_memory_map.sh --project . --full` to rebuild MEMORY_MAP.json
- Check that nodes have `## Change Log` sections with `[YYYY-MM-DD]` format dates
- For `--issues`, check that `## Open Issues` sections have non-empty, non-"None." entries

**"Tag filter returns nothing"**
- Verify the tag exists in MEMORY_MAP.md Tag Index
- Try Chinese aliases (e.g., `--tag 支付` instead of `--tag payment`)
- Without MEMORY_MAP.json, the script falls back to parsing frontmatter — slower but still works

**Script fails immediately**
- Check bash version: `bash --version` (need 4+)
- macOS: `brew install bash` then use `/opt/homebrew/bin/bash`
- Check Python: `python3 --version` (or `python --version`)
