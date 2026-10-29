#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""
Docutils syntax check for kernel media .rst files, without Sphinx.

Registers the kernel's own flat-table directive (Documentation/sphinx/
rstFlatTable.py, which only needs docutils) and no-op stand-ins for the
Sphinx-only directives and roles, parses each file, and prints the
messages. With --base REV, messages that also appear for the file at REV
are dropped, so only the new problems are shown.

Usage: rst_check.py KERNEL_TREE [--base REV] FILE...
"""

import importlib.util
import os
import re
import subprocess
import sys

from docutils import nodes, utils
from docutils.core import publish_doctree
from docutils.parsers.rst import Directive, directives, roles


def load_flat_table(tree):
    path = os.path.join(tree, 'Documentation/sphinx/rstFlatTable.py')
    spec = importlib.util.spec_from_file_location('rstFlatTable', path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    directives.register_directive('flat-table', mod.FlatTable)
    roles.register_canonical_role('cspan', mod.c_span)
    roles.register_canonical_role('rspan', mod.r_span)


class Noop(Directive):
    has_content = True
    optional_arguments = 10
    final_argument_whitespace = True
    option_spec = None

    def run(self):
        return []


def noop_role(name, rawtext, text, lineno, inliner, options=None,
              content=None):
    return [nodes.literal(rawtext, text)], []


def setup(tree):
    load_flat_table(tree)
    for d in ('c:type', 'c:macro', 'c:function', 'cssclass', 'kernel-doc',
              'toctree', 'only', 'tabularcolumns', 'raw'):
        directives.register_directive(d, Noop)
    for r in ('c:type', 'c:func', 'c:macro', 'ref', 'doc', 'c:member'):
        roles.register_canonical_role(r, noop_role)


def check(text, name):
    msgs = []

    class Collect:
        def write(self, s):
            msgs.extend(m for m in s.splitlines() if m.strip())

    publish_doctree(text, source_path=name, settings_overrides={
        'report_level': 2, 'halt_level': 5, 'warning_stream': Collect()})
    # Drop line numbers so that messages can be compared with the base.
    return [re.sub(r':\d+:', ':', m) for m in msgs
            if 'Unknown interpreted text role' not in m]


def main():
    tree = sys.argv[1]
    args = sys.argv[2:]
    base = None
    if args[:1] == ['--base']:
        base, args = args[1], args[2:]
    setup(tree)
    total = 0
    for f in args:
        new = check(open(os.path.join(tree, f)).read(), f)
        if base:
            old_text = subprocess.run(['git', '-C', tree, 'show',
                                       '%s:%s' % (base, f)],
                                      capture_output=True, text=True).stdout
            old = check(old_text, f)
            for m in old:
                if m in new:
                    new.remove(m)
        print('%s: %d new message(s)' % (f, len(new)))
        for m in new:
            print('   ' + m)
        total += len(new)
    sys.exit(1 if total else 0)


if __name__ == '__main__':
    main()
