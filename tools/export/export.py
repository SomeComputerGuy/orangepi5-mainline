#!/usr/bin/env python3
"""Refresh this repository from the Orange Pi 5 workspace (~/orangepi5).

Run through tools/export-from-workspace.sh. Everything this script writes is
generated; hand-written files (README.md, LICENSE, PUBLISH.md, docs/SOURCES.md,
tools/, ...) are never touched. See tools/export/README.md.
"""
import argparse, datetime, os, re, shutil, subprocess, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CONF = REPO / "tools/export/topics.conf"
EXCLUDE_FILE = REPO / "tools/export/exclude.conf"

USER_NAME = "Arun Iyengar"
USER_EMAIL = "aiyengar1990@gmail.com"
# Site-specific settings that must not be published live in .work/private/
# (ignored by git): redaction rules for private hostnames/addresses, extra
# author addresses that are the user's own, and the patch that makes the
# workspace scripts public. See tools/export/README.md.
PRIVATE = REPO / ".work/private"
OWN_EMAILS = {USER_EMAIL}
REDACT = []
SCRIPTS_PATCH = PRIVATE / "scripts-public.patch"
if (PRIVATE / "private.conf").exists():
    for line in (PRIVATE / "private.conf").read_text().splitlines():
        f = line.split("\t")
        if f[0] == "redact" and len(f) == 3:
            REDACT.append((f[1], f[2]))
        elif f[0] == "own-email" and len(f) >= 2:
            OWN_EMAILS.add(f[1])
else:
    print("WARNING: no .work/private/private.conf: nothing site-specific is redacted", file=sys.stderr)
TEST_SUBS = []
if (PRIVATE / "tests-public.conf").exists():
    for line in (PRIVATE / "tests-public.conf").read_text().splitlines():
        f = line.split("\t")
        if f[0] == "sub" and len(f) == 3:
            TEST_SUBS.append((re.compile(f[1], re.M), f[2]))
TESTS_CONF = REPO / "tools/export/tests.conf"
TEXT_EXT = {".md", ".txt", ".patch", ".diff", ".c", ".h", ".py", ".sh", ".dtso",
            ".yaml", ".rst", ".conf", ".cfg", ".config", ".dtsi", ".mk", ""}
OUT_TEXT_EXT = {".md", ".txt", ".c", ".h", ".py", ".sh", ".dtso", ".yaml", ".rst"}
OUT_SKIP_DIRS = {"patches", "patches-mc", "dt", "modules", "dtb", "deploy", "traces",
                 "test-kernel", "dbg", "hdr", "board-logs"}
OUT_MAX = 300 * 1024
LOCAL_RE = re.compile(r"DO[ -]NOT[ -]UPSTREAM|NOT[ -]FOR[ -]UPSTREAM|^DEBUG:|"
                      r"local backport only|not for upstream|local[ -]only|"
                      r"local fixup|squash into", re.I | re.M)


BACKUP_RE = re.compile(r"(\.bak[^/]*|~|\.orig|\.rej|\.swp)$")


def run(*args, cwd=None, check=True):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, errors="replace")
    if check and r.returncode:
        sys.exit(f"command failed: {' '.join(map(str, args))}\n{r.stderr}")
    return r.stdout


# AI-assistance attribution for our own patches, per the kernel's
# Documentation/process/coding-assistants.rst ("Assisted-by: LLM [TOOL1] ...";
# the model as one token, no tools: only basic tools were used). Other
# people's patches keep whatever tags their authors posted.
ASSISTED_BY = "Assisted-by: Claude:claude-opus-5-5"
CLAUDE_TRAILER_RE = re.compile(r"(?im)^(Co-Authored-By|Co-developed-by|Assisted-by):[^\n]*(claude|anthropic)[^\n]*\n")


def redact(s):
    for pat, rep in REDACT:
        s = re.sub(pat, rep, s)
    return s


def tag_assisted(text):
    """Our patches: drop Claude co-author trailers and end the trailer block
    with exactly one Assisted-by tag. Patches by anyone else: unchanged."""
    m = re.search(r"(?m)^From: (.*)$", text)
    if not m or not (USER_NAME in m.group(1) or any(e in m.group(1) for e in OWN_EMAILS)):
        return text
    # The commit message ends at the first "---" line (format-patch layout)
    sep = re.search(r"(?m)^---$", text)
    if not sep:
        return text
    msg, rest = text[:sep.start()], text[sep.start():]
    hdr, _, body = msg.partition("\n\n")
    body = CLAUDE_TRAILER_RE.sub("", body).rstrip("\n")
    last = body.rsplit("\n\n", 1)[-1] if body else ""
    # Append to an existing trailer block, otherwise start one
    if body and "\n\n" in body and all(re.match(r"^[A-Za-z-]+: \S", l) for l in last.splitlines()):
        body += "\n" + ASSISTED_BY
    else:
        body += ("\n\n" if body else "") + ASSISTED_BY
    return hdr + "\n\n" + body + "\n" + rest


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = redact(text)
    if path.suffix == ".patch":
        text = tag_assisted(text)
    path.write_text(text)


def copy_text(src, dst):
    write(dst, src.read_text(errors="replace"))
    if os.access(src, os.X_OK):
        dst.chmod(0o755)


def load_excludes():
    pats = []
    if EXCLUDE_FILE.exists():
        for line in EXCLUDE_FILE.read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            if line:
                pats.append(line)
    return pats


def excluded(rel, pats):
    from fnmatch import fnmatch
    return any(fnmatch(rel, p) or rel.startswith(p.rstrip("/") + "/") for p in pats)


class Topics:
    def __init__(self, linux):
        self.linux = linux
        self.boardbase_refs = []
        self.items = []
        for line in CONF.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if line.startswith("BOARDBASE="):
                self.boardbase_refs = line.split("=", 1)[1].split()
                continue
            f = [x.strip() for x in line.split(" | ")]
            if len(f) != 7:
                sys.exit(f"topics.conf: bad line: {line}")
            self.items.append(dict(zip(
                ["name", "branch", "parent", "out", "title", "hw", "next"], f)))
        self.byname = {t["name"]: t for t in self.items}

    def git(self, *a, check=True):
        return run("git", "-C", str(self.linux), *a, check=check)

    def rev(self, spec):
        if spec == "@boardbase":
            return self.git("merge-base", "--octopus", *self.boardbase_refs).strip()
        if spec in self.byname:
            return self.byname[spec]["tip"]
        return self.git("rev-parse", "--verify", "-q", spec + "^{commit}").strip()


def upstream_base(topics, t):
    p = t["parent"]
    while p in topics.byname:
        p = topics.byname[p]["parent"]
    return p


def export_topic(topics, t, ws, dest):
    g = topics.git
    tip, ptip = t["tip"], topics.rev(t["parent"])
    base = g("merge-base", tip, ptip).strip()
    t["base"] = base
    commits = g("rev-list", "--reverse", "--topo-order", "--no-merges", f"{base}..{tip}").split()
    if g("rev-list", "--merges", "--count", f"{base}..{tip}").strip() != "0":
        sys.exit(f"{t['name']}: merge commits in {base}..{tip}; not supported")
    d = dest / t["name"]
    rows, series = [], []
    counts = {"ours": 0, "carried": 0, "local": 0}
    for i, c in enumerate(commits, 1):
        ae, an, subj, slug = g("log", "-1", "--format=%ae%x00%an%x00%s%x00%f", c).rstrip("\n").split("\x00")
        body = g("log", "-1", "--format=%b", c)
        if LOCAL_RE.search(subj) or LOCAL_RE.search(body):
            cat = "local"
        elif ae in OWN_EMAILS:
            cat = "ours"
        else:
            cat = "carried"
        counts[cat] += 1
        links = re.findall(r"^Link:\s*(\S+)", body, re.M)
        fname = f"{i:04d}-{slug[:52]}.patch"
        patch = g("format-patch", "-1", "--stdout", "--zero-commit", "--no-signature",
                  "-N", "--binary", c)
        write(d / cat / fname, patch)
        series.append(f"{cat}/{fname} {c}")
        who = USER_NAME if ae in OWN_EMAILS else an
        rows.append((i, cat, subj, who, links))
    d.mkdir(parents=True, exist_ok=True)
    (d / "series").write_text(
        "# Apply in this order on top of the parent topic (see topic.env):\n"
        "#   while read -r p sha; do git am \"$p\"; done < <(grep -v '^#' series)\n"
        "# Second column: the original commit in the workspace clone (for reference).\n"
        + "".join(s + "\n" for s in series))
    tree = g("rev-parse", tip + "^{tree}").strip()
    (d / "topic.env").write_text(
        f"NAME={t['name']}\nWORKSPACE_BRANCH={t['branch']}\nPARENT={t['parent']}\n"
        f"UPSTREAM_BASE={upstream_base(topics, t)}\nBASE_ORIG={base}\nTIP_ORIG={tip}\n"
        f"TIP_TREE={tree}\nCOMMITS={len(commits)}\n")
    t.update(counts=counts, rows=rows, ncommits=len(commits))

    # Notes, results and test tools from work/_out/<out>
    docs = []
    excl = load_excludes()
    if t["out"] != "-":
        src = ws / "work/_out" / t["out"]
        for p in sorted(src.rglob("*")):
            rel = p.relative_to(src)
            relw = f"{t['out']}/{rel.as_posix()}"
            if not p.is_file() or BACKUP_RE.search(p.name) or any(x in OUT_SKIP_DIRS for x in rel.parts[:-1]):
                continue
            if excluded(relw, excl):
                continue
            name = p.name.lower()
            is_cover = name.startswith("cover-letter") or name.startswith("cover_letter")
            if not (p.suffix.lower() in OUT_TEXT_EXT or p.name == "Makefile") or p.stat().st_size > OUT_MAX:
                continue
            if b"\0" in p.read_bytes()[:8192]:
                continue
            target = d / ("cover-letter.txt" if is_cover and len(rel.parts) == 1 else Path("notes") / rel)
            copy_text(p, target)
            docs.append(target.relative_to(d).as_posix())
    t["docs"] = docs
    if counts["ours"] and "cover-letter.txt" not in docs:
        write(d / "cover-letter.draft.txt", draft_cover(t))
    write(d / "README.md", topic_readme(t))


def draft_cover(t):
    ours = [r for r in t["rows"] if r[1] == "ours"]
    carried = sorted({l for r in t["rows"] if r[1] == "carried" for l in r[4]})
    lines = [f"Subject: [PATCH 0/{len(ours)}] <subsystem>: {t['title']}", "",
             "DRAFT generated by tools/export: replace the TODOs before sending.", "",
             "TODO: what the series does and why.", "",
             f"Tested on an Orange Pi 5 (RK3588S), Linux 7.3: {t['hw']}.",
             "Details: notes/RESULTS.md in this topic directory." if any(x.endswith("RESULTS.md") for x in t["docs"]) else "", ""]
    if carried:
        lines += ["Depends on (applied in the test branch before these patches):"]
        lines += [f"  {l}" for l in carried[:40]] + [""]
    lines += [f"{USER_NAME} ({len(ours)}):"] + [f"  {r[2]}" for r in ours] + [""]
    return "\n".join(lines)


def md_escape(s):
    return s.replace("|", "\\|")


def topic_readme(t):
    c = t["counts"]
    out = [f"# {t['name']}: {t['title']}", "",
           f"- Workspace branch: `{t['branch']}` (exported {datetime.date.today()})",
           f"- Kernel fork branch: `opi5/{t['name']}` (see PUBLISH.md)",
           f"- Sits on: `{t['parent']}` (base commit `{t['base'][:12]}`)",
           f"- Hardware test: {t['hw']}",
           f"- Next upstream step: {t['next']}",
           f"- Patches: {t['ncommits']} = {c['ours']} ours, {c['carried']} carried from others, {c['local']} local-only", "",
           "Apply with `git am` in the order listed in [`series`](series), on top of the parent topic "
           "(or check out the fork branch). Patch numbers are the position in that order.", ""]
    sections = [("ours", "(a) Ours, intended for upstream (`ours/`)"),
                ("carried", "(b) Carried from others, authorship kept (`carried/`)"),
                ("local", "(c) Local only / DO NOT UPSTREAM (`local/`)")]
    for cat, head in sections:
        rows = [r for r in t["rows"] if r[1] == cat]
        if not rows:
            continue
        out += [f"## {head}", "", "| # | Subject | Author | Link |", "|---|---|---|---|"]
        for i, _, subj, who, links in rows:
            ln = " ".join(f"[link]({l})" for l in links[:2]) if links else ""
            out.append(f"| {i:04d} | {md_escape(subj)} | {md_escape(who)} | {ln} |")
        out.append("")
    if t["docs"]:
        out += ["## Notes, results and test tools", ""]
        out += [f"- [{x}]({x})" for x in t["docs"]] + [""]
    if (t.get("draft")):
        pass
    return "\n".join(out)


def export_static(ws, repo):
    # scripts/ (+ public portability patch), install-deps.sh
    sd = repo / "scripts"
    shutil.rmtree(sd, ignore_errors=True)
    for p in sorted((ws / "scripts").iterdir()):
        if p.is_file() and not BACKUP_RE.search(p.name):
            sd.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, sd / p.name)   # raw: the patch applies to the originals
    if not SCRIPTS_PATCH.exists():
        sys.exit(f"missing {SCRIPTS_PATCH} (see tools/export/README.md)")
    r = subprocess.run(["patch", "-s", "-p1", "--no-backup-if-mismatch", "-d", str(sd), "-i", str(SCRIPTS_PATCH)],
                       capture_output=True, text=True)
    if r.returncode:
        sys.exit(".work/private/scripts-public.patch no longer applies to the workspace scripts:\n"
                 + r.stdout + r.stderr + "\nUpdate the patch (see tools/export/README.md).")
    for p in sd.iterdir():
        write(p, p.read_text())
        if p.suffix in (".sh", ".py"):
            p.chmod(0o755)
    copy_text(ws / "install-deps.sh", repo / "install-deps.sh")
    # patches/ (U-Boot dtsi fragments, TF-A, upstream U-Boot, Linux board patches)
    pd = repo / "patches"
    shutil.rmtree(pd, ignore_errors=True)
    for p in sorted((ws / "patches").rglob("*")):
        rel = p.relative_to(ws / "patches")
        # skip backup files and whole backup directories (e.g. linux.bak-20261029/)
        if p.is_file() and not any(BACKUP_RE.search(part) for part in rel.parts):
            copy_text(p, pd / rel)
    # overlay/, cidata/ (user-data becomes the example; the real one is local)
    od = repo / "overlay"
    shutil.rmtree(od, ignore_errors=True)
    for p in sorted((ws / "overlay").rglob("*")):
        if p.is_file() and not BACKUP_RE.search(p.name):
            copy_text(p, od / p.relative_to(ws / "overlay"))
    # overlay-desktop/: extra files for the desktop image (build-image.sh --variant desktop)
    odd = repo / "overlay-desktop"
    shutil.rmtree(odd, ignore_errors=True)
    if (ws / "overlay-desktop").is_dir():
        for p in sorted((ws / "overlay-desktop").rglob("*")):
            if p.is_file() and not BACKUP_RE.search(p.name):
                copy_text(p, odd / p.relative_to(ws / "overlay-desktop"))
    cd = repo / "cidata"
    shutil.rmtree(cd, ignore_errors=True)
    for n in ("meta-data", "network-config"):
        copy_text(ws / "cidata" / n, cd / n)
    ud = (ws / "cidata/user-data").read_text()
    write(cd / "user-data.example", ud)
    # docs from the workspace
    dd = repo / "docs/workspace"
    shutil.rmtree(dd, ignore_errors=True)
    for p in sorted((ws / "docs").glob("*.md")):
        copy_text(p, dd / p.name)
    for extra in ("work/_out/GSTREAMER-FOLLOWUPS.md",):
        if (ws / extra).exists():
            copy_text(ws / extra, dd / Path(extra).name)
    # Image-kernel integration notes (MANIFEST.md: which patches/linux range
    # comes from which branch, test and upstream state), whatever is there
    idir = ws / "work/_out/integration"
    md = repo / "docs/image-kernel"
    shutil.rmtree(md, ignore_errors=True)
    if idir.is_dir():
        for p in sorted(idir.rglob("*")):
            rel = p.relative_to(idir)
            if (p.is_file() and p.suffix.lower() in OUT_TEXT_EXT and p.stat().st_size <= OUT_MAX
                    and not any(x in OUT_SKIP_DIRS for x in rel.parts[:-1])
                    and b"\0" not in p.read_bytes()[:8192]):
                copy_text(p, md / rel)


def script_header(text):
    """The leading comment block of a script (after the shebang / SPDX line)."""
    out = []
    lines = text.splitlines()
    if lines and lines[0].startswith("#!"):
        lines = lines[1:]
    if lines and lines[0].lstrip().startswith('"""'):        # Python docstring
        doc = []
        for i, l in enumerate(lines):
            doc.append(l.replace('"""', ""))
            if i and '"""' in l or (i == 0 and l.count('"""') == 2):
                break
        return [l.rstrip() for l in doc if l.strip()][:25]
    for l in lines:
        st = l.strip()
        if st.startswith("//") or st.startswith("/*") or st.startswith("*"):
            st = st.lstrip("/*").strip()
        elif st.startswith("#"):
            st = st[1:].strip()
        elif not st:
            if out:
                break
            continue
        else:
            break
        if st.startswith("SPDX-License-Identifier"):
            continue
        out.append(st)
    return out[:25]


def export_tests(ws, repo):
    """tests/<name>/: board/host test scripts from work/_out, made portable
    (TEST_SUBS), redacted, with a generated README."""
    td = repo / "tests"
    shutil.rmtree(td, ignore_errors=True)
    if not TESTS_CONF.exists():
        return []
    excl = load_excludes()
    done = []
    for line in TESTS_CONF.read_text().splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        f = [x.strip() for x in line.split(" | ")]
        if len(f) != 6:
            sys.exit(f"tests.conf: bad line: {line}")
        name, sources, where, topic, title, runline = f
        files = []
        for pat in sources.split():
            hits = sorted((ws / "work/_out").glob(pat))
            if not hits:
                sys.exit(f"tests.conf: {name}: nothing matches {pat}")
            for p in hits:
                rel = p.relative_to(ws / "work/_out").as_posix()
                if (not p.is_file() or BACKUP_RE.search(p.name) or excluded(rel, excl)
                        or p.stat().st_size > OUT_MAX or b"\0" in p.read_bytes()[:8192]):
                    continue
                files.append(p)
        d = td / name
        rows = []
        # keep the layout the scripts were run with (e.g. lib/, tools/, scripts/ next to the wrapper)
        base = Path(os.path.commonpath([str(p.parent) for p in files])) if files else None
        for p in files:
            rel = p.relative_to(base).as_posix()
            text = p.read_text(errors="replace")
            for rx, rep in TEST_SUBS:
                text = rx.sub(rep, text)
            write(d / rel, text)
            if os.access(p, os.X_OK) or p.suffix in (".sh", ".py") or text.startswith("#!"):
                (d / rel).chmod(0o755)
            rows.append((rel, script_header(redact(text))))
        L = [f"# {name}: {title}", "",
             f"- Runs on: **{where}**" + (" (copy this directory to the board, e.g. with `scp -r`)" if where != "host" else ""),
             f"- How it was run: `{runline}`"]
        if topic != "-":
            L.append(f"- Notes and detailed results: [`topics/{topic}/`](../../topics/{topic}/README.md)")
        L += ["- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: "
              "[`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)", "",
              "These are the scripts exactly as they were run on the test board, except that the lab's own "
              "values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), "
              "`OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` "
              "subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` "
              "or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). "
              "C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: "
              "see the file's header).", "", "## Files", ""]
        for fn, hdr in rows:
            L.append(f"### [`{fn}`]({fn})")
            L.append("")
            if hdr:
                L += ["```"] + hdr + ["```"]
            L.append("")
        write(d / "README.md", "\n".join(L))
        done.append((name, len(files)))
    return done


def status_md(topics, repo):
    today = datetime.date.today()
    L = [f"# Status (generated {today} by tools/export-from-workspace.sh)", "",
         "Every kernel topic, the branch it lives on, how far it got, and the next upstream step.",
         "`Ours/Carried/Local` count the patches in each category (see the topic README).",
         "Nothing here has been sent upstream yet.", "",
         "## Kernel topics (Linux v7.3 unless noted)", "",
         "| Topic | What | Sits on | Ours / Carried / Local | Tested on hardware (Orange Pi 5) | Next step |",
         "|---|---|---|---|---|---|"]
    for t in topics.items:
        c = t["counts"]
        L.append(f"| [{t['name']}](topics/{t['name']}/README.md) | {md_escape(t['title'])} | "
                 f"`{t['parent']}` | {c['ours']} / {c['carried']} / {c['local']} | "
                 f"{md_escape(t['hw'])} | {md_escape(t['next'])} |")
    L += ["", "## Image kernel", "",
          "`patches/linux/` is what `scripts/build-kernel.sh` applies on v7.3 for the image "
          "(recreated as fork branch `opi5/image-7.3`). It is a snapshot of the topics that "
          "were ready for the image; the topic directories are the reference for upstreaming."
          + (" Range-by-range provenance and test state: [docs/image-kernel/MANIFEST.md](docs/image-kernel/MANIFEST.md)."
             if (repo / "docs/image-kernel/MANIFEST.md").exists() else ""), "",
          f"Patches in patches/linux: {len(list((repo / 'patches/linux').glob('*.patch')))}; other patch "
          "directories: " + (", ".join(sorted(d.name for d in (repo / 'patches').iterdir() if d.is_dir() and d.name != 'linux')) or "none") + ".", "",
          "## U-Boot and TF-A", "",
          "| Patch | Where | Tested | Next step |", "|---|---|---|---|",
          "| ata: dwc_ahci: Look up the PHY on sata-port subnodes too | patches/upstream/u-boot | yes (boots from M.2 SATA) | send (scripts/send-uboot-patches.sh) |",
          "| RFC rockchip: rk3588: Raise the Cortex-A76 cluster clocks to 1.2 GHz | patches/upstream/u-boot | yes (boot time 100 s -> normal) | send as RFC |",
          "| Board -u-boot.dtsi fragments (SATA, M.2 auto-detect, big-core clocks) | patches/u-boot | yes (in the image) | the cpuclk part is covered by the RFC above |",
          "| fix(rk3588): save and restore the PHP CRU clock gate state | patches/tf-a | not yet (suspend untested) | test suspend, then TF-A Gerrit |",
          "", "## Not published", "",
          "- `opi5/vepu580` (and `_out/vepu580*`): port of an out-of-tree, vendor-derived encoder driver by other authors, marked NOT FOR UPSTREAM; superseded by the `rkvenc` topic.",
          "- `opi5/*-debug` branches: fault-injection debugging only.",
          "- `opi5/shutdown-hang-7.3-clk`: same commits as `shutdown-hang`.",
          "- Built modules, DTBs, images, logs larger than 300 KiB, vendor sources and downloads (see docs/SOURCES.md).", ""]
    (repo / "STATUS.md").write_text("\n".join(L))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workspace", default=os.path.expanduser("~/orangepi5"))
    ap.add_argument("--linux", help="kernel clone (default: <workspace>/src/linux)")
    a = ap.parse_args()
    ws = Path(a.workspace)
    linux = Path(a.linux) if a.linux else ws / "src/linux"
    export_static(ws, REPO)
    for name, n in export_tests(ws, REPO):
        print(f"  tests/{name:16} {n} files")
    topics = Topics(linux)
    dest = REPO / "topics"
    shutil.rmtree(dest, ignore_errors=True)
    for t in topics.items:
        t["tip"] = topics.rev(t["branch"])
    for t in topics.items:
        export_topic(topics, t, ws, dest)
        c = t["counts"]
        print(f"  {t['name']:20} {t['ncommits']:4} commits ({c['ours']} ours, {c['carried']} carried, {c['local']} local), {len(t['docs'])} notes")
    status_md(topics, REPO)


if __name__ == "__main__":
    main()
