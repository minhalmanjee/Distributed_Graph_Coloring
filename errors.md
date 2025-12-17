C Code Fixes did:
NULL Pointer Crash in Lock Acquisition - Added NULL and REDIS_REPLY_NIL checks
Memory Leak in set_node_color - memory cleanup for custom allocated replies
WAIT Command Infinite Retry Loop - retry logic (infinite for 0 ACKs, max 3 for partial)
WAIT Command Skip When required_replicas = 0 - Early return optimization
SET Command Error Handling - Added error checking before WAIT


1. Missing WAIT and Replication Commands in Statistics Logging

Initially, the server statistics output only included read and write operations. Metrics for WAIT commands and replication-related commands were missing, even though they were important for evaluating coordination and replication overhead.

Two additional atomic counters were added to track, the number of WAIT commands processed
the number of replication-related commands (e.g., REPLCONF, PSYNC, REPLPING), The periodic statistics logger was updated to include these values in the server log output.

2. Jemalloc Linking Error During Compilation

Compilation failed with an undefined reference to __isoc23_strtol, causing the build process to abort. The bundled jemalloc library had been compiled against an older version of glibc. The system’s newer glibc required symbols that were not present in the old build.
jemalloc is now rebuilt on each target machine before compiling KeyDB, ensuring compatibility with the system’s glibc version.

3. Status Keys Not Written to Monitoring Server

Client processes completed graph coloring, but the monitoring script waited indefinitely because status keys never appeared in the monitoring KeyDB instance.
Error checking added to ensure the connection is valid before attempting to write the status key.

4. The busy-wait loop accessed ->str fields of Redis replies without checking whether:

the reply pointer was NULL, or

the reply type was REDIS_REPLY_NIL (key does not exist)
Additional NULL and type checks were added before accessing reply fields. Replies are now safely freed and reissued inside the loop.  The lock acquisition logic is working against missing or NIL Redis replies.




6. Memory Leak in set_node_color()
Memory usage increased over time due to leaked Redis replies.
The write_with_wait() function returns custom-allocated reply structures that must be freed manually. These were not being released properly in set_node_color(). Explicit cleanup added to free both the reply structure and its fields.

7. program could hang indefinitely when a WAIT command never received enough acknowledgments from replicas. There was no retry limit for partial acknowledgments.
Now, Infinite retries when zero replicas acknowledge (replication may still catch up)
A maximum of three retries when some replicas acknowledge but not enough

8. The WAIT command was executed even when required_replicas was set to zero.

9. Explicit validation was added to ensure the SET command succeeded before continuing.

10. Graph loading (Protocol + KEYDB CLI PIPE) was slow due to writing protocol data to intermediate files.
script output is now piped directly into keydb-cli --pipe over SSH.


