# Notes for coding agents

[CONTRIBUTING.md](CONTRIBUTING.md) holds the project's conventions: follow it in full, and
OpenReliant's own [CONTRIBUTING.md](https://github.com/OpenReliant/openreliant/blob/main/CONTRIBUTING.md)
where this one points to it. These notes add how the maintainer works with an agent.

- **Starting an issue.** Begin with `gh issue view N --comments`, and read the comments on related
  closed issues too, in this repository and in OpenReliant's.
- **Trying a change.** When the maintainer tries a change, build and launch the editor right away:
  `make run ARGS='<mod folder>'`. Once they are happy with it, run the checks and commit.
- **Checking a screen.** `openreliant-editor <mod folder> --screenshot <file.png>` draws without a
  window and saves the frame, for checking a screen against `design/` without showing a window on
  the maintainer's screen. `--show`, `--line` and `--game` set up what it shows.
- **Pull requests.** Push the feature branch and open the pull request when the change is ready.
  The maintainer merges it. See one pull request merged before starting the next feature.
- **Attribution.** Commits and pull requests carry the maintainer's git identity alone. End commit
  messages and pull request bodies with their content, leaving out trailers such as
  `Co-Authored-By` and "Generated with" footers.
- **Gaps.** File an issue for each gap you leave, and name the issues in your reply.
- **Plain English.** Write docs, comments, messages, issues, pull requests and replies in plain,
  simple technical English, the way you would explain the code to a colleague: normal word order,
  common words, short sentences.
- **Replies.** Use the docs' punctuation in replies too: no em or en dashes.
