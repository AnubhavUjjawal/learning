- The tests were run on a Raspberry PI 5 (8GB Ram) because I don't own any other linux PC.
- Buffer caches were dropped before `read` and `mmap` runs

```
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ strace -c ./zig-out/bin/read_vs_mmap generate-file build.random 4096
[debug]: generating a large file
[debug]: cwd: /home/anubhav/Desktop/learning/read_vs_mmap, filepath: build.random filesize(in kb): 4194304
[debug]: random string slice check: { 49, 50, 51, 52, 53 }
[debug]: file generated
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
100.00    3.278982           6    524288           write
  0.00    0.000027           3         9           writev
  0.00    0.000000           0         1           flock
  0.00    0.000000           0         1         1 faccessat
  0.00    0.000000           0         4           openat
  0.00    0.000000           0         3           close
  0.00    0.000000           0         1           read
  0.00    0.000000           0         1           readlinkat
  0.00    0.000000           0         2           fstat
  0.00    0.000000           0         1           set_tid_address
  0.00    0.000000           0         1           set_robust_list
  0.00    0.000000           0         5           rt_sigaction
  0.00    0.000000           0         1           gettid
  0.00    0.000000           0         3           brk
  0.00    0.000000           0         3           munmap
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         5           mmap
  0.00    0.000000           0         4           mprotect
  0.00    0.000000           0         3           prlimit64
  0.00    0.000000           0         1           getrandom
  0.00    0.000000           0         1           rseq
------ ----------- ----------- --------- --------- ----------------
100.00    3.279009           6    524339         1 total
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ strace -c -w ./zig-out/bin/read_vs_mmap generate-file build.random 4096
[debug]: generating a large file
[debug]: cwd: /home/anubhav/Desktop/learning/read_vs_mmap, filepath: build.random filesize(in kb): 4194304
[debug]: random string slice check: { 49, 50, 51, 52, 53 }
[debug]: file generated
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
100.00   42.409056          80    524288           write
  0.00    0.000324          35         9           writev
  0.00    0.000221         221         1           execve
  0.00    0.000121          30         4           openat
  0.00    0.000070          13         5           mmap
  0.00    0.000056          14         4           mprotect
  0.00    0.000041           8         5           rt_sigaction
  0.00    0.000041          13         3           munmap
  0.00    0.000040          19         2           fstat
  0.00    0.000031          31         1           readlinkat
  0.00    0.000029           9         3           brk
  0.00    0.000027           9         3           prlimit64
  0.00    0.000026           8         3           close
  0.00    0.000014          14         1         1 faccessat
  0.00    0.000012          12         1           flock
  0.00    0.000010          10         1           read
  0.00    0.000010           9         1           getrandom
  0.00    0.000008           8         1           gettid
  0.00    0.000008           8         1           rseq
  0.00    0.000008           8         1           set_tid_address
  0.00    0.000008           7         1           set_robust_list
------ ----------- ----------- --------- --------- ----------------
100.00   42.410161          80    524339         1 total
```

- [This trace](./writesyscalltrace.svg) was taken when creating a 4GB file (filling it with static string) in 8KB blocks on RPI 5.
Notes: 
- `sudo perf record -g <command to be examined>`
- sudo makes sure system calls are in the trace
- `-g` records stack trace
- https://man7.org/linux/man-pages/man1/perf.1.html


Then use [flame graphs](https://github.com/brendangregg/FlameGraph) to generate SVG
