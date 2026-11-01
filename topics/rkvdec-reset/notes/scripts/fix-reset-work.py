#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# fix-reset-work.py <linux tree>: CCU reset work: act only on a pending reset, keep every deferred context
import sys
d = sys.argv[1] + '/drivers/media/platform/rockchip/rkvdec/'
def sub(f, old, new, n=1):
	p = d + f; s = open(p).read()
	assert s.count(old) == n, (f, old[:60], s.count(old))
	open(p, 'w').write(s.replace(old, new))

sub('rkvdec.h', '''	bool ccu_reset_pending;
	struct rkvdec_ctx *deferred_ctx;
''', '''	bool ccu_reset_pending;
	struct list_head deferred_ctxs;
''')
sub('rkvdec.h', '''	int film_idx;
	void *priv;''', '''	int film_idx;
	/* m2m jobs to run once the cores are reset, see rkvdec_job_start() */
	struct list_head deferred_node;
	unsigned int num_deferred;
	void *priv;''')
sub('rkvdec.c', '''		rkvdec->deferred_ctx = ctx;
		return ERR_PTR(-EAGAIN);''', '''		if (!ctx->num_deferred++)
			list_add_tail(&ctx->deferred_node, &rkvdec->deferred_ctxs);
		return ERR_PTR(-EAGAIN);''')
sub('rkvdec.c', '''	INIT_LIST_HEAD(&ctx->jobs);''', '''	INIT_LIST_HEAD(&ctx->jobs);
	INIT_LIST_HEAD(&ctx->deferred_node);''')
# the reset work
sub('rkvdec.c', '''	struct rkvdec_ctx *ctx;
	bool powered;
	int i;

''', '''	struct rkvdec_ctx *ctx;
	unsigned int runs;
	bool powered;
	int i;

	/*
	 * Each failure schedules the work, and one reset handles all the
	 * failures up to it: a run without a reset pending must not touch the
	 * cores, which run new jobs again.
	 */
	scoped_guard(spinlock_irqsave, &rkvdec->cores_lock)
		if (!rkvdec->ccu_reset_pending)
			return;

''')
s = open(d + 'rkvdec.c').read()
i = s.index('''	scoped_guard(spinlock_irqsave, &rkvdec->cores_lock) {
		rkvdec->ccu_reset_pending = false;''')
j = s.index('}\n', s.index('rkvdec_device_run(ctx);', i)) + 2
s = s[:i] + '''	/*
	 * Run the m2m jobs that couldn't start meanwhile, of all the contexts:
	 * each one waits for its job to be run.
	 */
	spin_lock_irq(&rkvdec->cores_lock);
	rkvdec->ccu_reset_pending = false;
	while (!rkvdec->ccu_reset_pending &&
	       (ctx = list_first_entry_or_null(&rkvdec->deferred_ctxs,
					       struct rkvdec_ctx, deferred_node))) {
		list_del_init(&ctx->deferred_node);
		runs = ctx->num_deferred;
		ctx->num_deferred = 0;
		spin_unlock_irq(&rkvdec->cores_lock);
		while (runs--)
			rkvdec_device_run(ctx);
		spin_lock_irq(&rkvdec->cores_lock);
	}
	spin_unlock_irq(&rkvdec->cores_lock);
}
''' + s[j:]
open(d + 'rkvdec.c', 'w').write(s)
s = open(d + 'rkvdec.c').read()
assert 'deferred_ctx;' not in s and 'deferred_ctx =' not in s, 'leftover deferred_ctx'
sub('rkvdec.c', '''	init_waitqueue_head(&rkvdec->reset_wq);''', '''	init_waitqueue_head(&rkvdec->reset_wq);
	INIT_LIST_HEAD(&rkvdec->deferred_ctxs);''')
