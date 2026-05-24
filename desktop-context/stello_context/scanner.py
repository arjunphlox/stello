"""FSEvents watcher + initial walk on watched folders.

Filled in at step 4 with `watchdog`. Enqueues per-file processing
into the enrich queue (single FIFO worker so MLX calls stay serialized).
"""
