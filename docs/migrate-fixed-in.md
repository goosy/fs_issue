# Migrating from `fixed_in`

Issue files written before fs-issue's first release may contain a `fixed_in` front matter key, which listed the commits that fixed the issue. The key no longer exists: the commit messages are now the only record of fixing commits, marked `fixissue#<id>` (spec, section 8). A file that still has the key fails `issue check`.

Migrate each repository once, in a single commit:

1. Remove the `fixed_in:` line from the front matter of every issue file, for example:

   ```sh
   sed -i '/^fixed_in:/d' issues/*.md
   ```

2. Commit the change with a message that lists every `fixed` issue on its own line, as a `fixissue#<id>` marker followed by the full IDs of its fixing commits, taken from the removed `fixed_in` values (expand abbreviated IDs with `git rev-parse <commit>`):

   ```
   chore: move fixed_in into commit messages

   fixissue#2kn5yrqz 642e037c1f3b9a8d5e2f4c6b7a8d9e0f1a2b3c4d 5ffeb05a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e
   fixissue#yqq38rn8 81d0a4e2c7b6a5f4e3d2c1b0a9f8e7d6c5b4a3f2
   ```

   - A `fixed` issue whose `fixed_in` was `[]`: find its fixing commits among `git log --grep="issue#<id>"` and list those.
   - An issue that is not `fixed` but had a non-empty `fixed_in`: settle its status first; list it only if it becomes `fixed`.

This commit is the one exception to the meaning of `fixissue#<id>`: it fixes nothing itself and points to the commits that did. `git log --grep="fixissue#<id>"` finds it for the issues fixed before the migration, and the real fixing commits for those fixed after.

## Empty heading declarations

The same early files also carry empty `problem_title:`, `proposal_title:` and `decision_title:` lines. These keys are now either absent or set (spec, section 3.3), so an empty one fails `issue check`. Remove the empty lines in the same commit; the headings stay `Problem`, `Proposal` and `Decision`:

```sh
sed -i -E '/^(problem|proposal|decision)_title:[[:space:]]*(#.*)?$/d' issues/*.md
```
