- The tests were run on a Raspberry PI 5 (8GB Ram) because I don't own any other linux PC.
- Buffer caches were dropped `sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'` before `read` and `mmap` runs

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


- https://unix.stackexchange.com/a/87909/426227 (drop os page cache before reads for cold reads)
```
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1723024      427280      171008     6497568     6533440
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ strace -c ./zig-out/bin/read_vs_mmap read-file-mmap build.random 16 100000
[debug]: reading the large file using mmap
[debug]: filepath: build.random, blocksize: 16, iterations: 100000
[debug]: filestat: .{ .inode = 1069678, .size = 4294967296, .mode = 33204, .kind = .file, .atime = 1768635170826926264, .mtime = 1768635216690910817, .ctime = 1768635216690910817 }
[debug]: initial byte: 12345678, mmap len: 4294967296
[debug]: seed: 16268764965554655849
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
100.00    0.048122       16040         3           munmap
  0.00    0.000000           0         1           flock
  0.00    0.000000           0         1         1 faccessat
  0.00    0.000000           0         3           openat
  0.00    0.000000           0         2           close
  0.00    0.000000           0         1           read
  0.00    0.000000           0        12           writev
  0.00    0.000000           0         2           fstat
  0.00    0.000000           0         1           set_tid_address
  0.00    0.000000           0         1           set_robust_list
  0.00    0.000000           0         5           rt_sigaction
  0.00    0.000000           0         2           rt_sigprocmask
  0.00    0.000000           0         1           gettid
  0.00    0.000000           0         3           brk
  0.00    0.000000           0         1           execve
  0.00    0.000000           0         8           mmap
  0.00    0.000000           0         3           mprotect
  0.00    0.000000           0         3           prlimit64
  0.00    0.000000           0         2           getrandom
  0.00    0.000000           0         1           statx
  0.00    0.000000           0         1           rseq
------ ----------- ----------- --------- --------- ----------------
100.00    0.048122         844        57         1 total
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1667776     1982976      171040     4923104     6588688
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ time ./zig-out/bin/read_vs_mmap read-file-mmap build.random 16 100000
[debug]: reading the large file using mmap
[debug]: filepath: build.random, blocksize: 16, iterations: 100000
[debug]: filestat: .{ .inode = 1069678, .size = 4294967296, .mode = 33204, .kind = .file, .atime = 1768635170826926264, .mtime = 1768635216690910817, .ctime = 1768635216690910817 }
[debug]: initial byte: 12345678, mmap len: 4294967296
[debug]: seed: 3664577440173585606

real    0m49.477s
user    0m0.268s
sys     0m0.985s
```

- [This trace](./mmapcalltrace.svg) was taken when doing random mmap reads on a 4GB file in 16KB blocks 100000 times on RPI 5.

```
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1664480     2066192      171040     4842304     6591984
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo strace -c ./zig-out/bin/read_vs_mmap read-file-pread build.random 16 100000
[debug]: reading the large file using pread
[debug]: filepath: build.random, blocksize: 16, iterations: 100000
[debug]: filestat: .{ .inode = 1069678, .size = 4294967296, .mode = 33204, .kind = .file, .atime = 1768635170826926264, .mtime = 1768635216690910817, .ctime = 1768635216690910817 }
[debug]: seed: 13226640330908188399
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 99.97    1.738837          17    100000           pread64
  0.02    0.000272         272         1           execve
  0.00    0.000065           6        10           writev
  0.00    0.000057           8         7           mmap
  0.00    0.000029           9         3           openat
  0.00    0.000028           9         3           mprotect
  0.00    0.000025          25         1           statx
  0.00    0.000024           8         3           munmap
  0.00    0.000014           2         5           rt_sigaction
  0.00    0.000013           4         3           close
  0.00    0.000012           4         3           brk
  0.00    0.000011           3         3           prlimit64
  0.00    0.000010           5         2           fstat
  0.00    0.000009           4         2           rt_sigprocmask
  0.00    0.000008           4         2           getrandom
  0.00    0.000006           6         1           flock
  0.00    0.000006           6         1         1 faccessat
  0.00    0.000005           5         1           read
  0.00    0.000004           4         1           gettid
  0.00    0.000004           4         1           rseq
  0.00    0.000003           3         1           set_tid_address
  0.00    0.000003           3         1           set_robust_list
------ ----------- ----------- --------- --------- ----------------
100.00    1.739445          17    100055         1 total
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1676224     2710144      171056     4188608     6580240
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ time ./zig-out/bin/read_vs_mmap read-file-pread build.random 16 100000
[debug]: reading the large file using pread
[debug]: filepath: build.random, blocksize: 16, iterations: 100000
[debug]: filestat: .{ .inode = 1069678, .size = 4294967296, .mode = 33204, .kind = .file, .atime = 1768635170826926264, .mtime = 1768635216690910817, .ctime = 1768635216690910817 }
[debug]: seed: 17069831048482261287

real    0m39.063s
user    0m0.028s
sys     0m1.453s
```

- [This trace](./preadsyscalltrace.svg) was taken when doing random syscall preads on a 4GB file in 16KB blocks 100000 times on RPI 5.

```
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1530432     3249280       96800     3653696     6726032
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ time ./zig-out/bin/read_vs_mmap read-file-pread build.random 16 100000

real    0m34.789s
user    0m0.014s
sys     0m1.482s
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1524640     3886560       96800     3024640     6731824
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ time ./zig-out/bin/read_vs_mmap read-file-mmap build.random 16 100000

real    0m39.625s
user    0m0.282s
sys     0m1.805s
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1522944     3877552       96800     3035760     6733520
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ time ./zig-out/bin/read_vs_mmap read-file-pread --aligned build.random 16 100000

real    0m24.513s
user    0m0.024s
sys     0m1.317s
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1542720     4778272       96800     2114400     6713744
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ time ./zig-out/bin/read_vs_mmap read-file-mmap --aligned build.random 16 100000

real    0m24.908s
user    0m0.239s
sys     0m1.115s
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1547568     4757824       96800     2127552     6708896
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo perf stat -e page-faults,major-faults,minor-faults \
  ./zig-out/bin/read_vs_mmap read-file-pread --aligned build.random 16 100000

 Performance counter stats for './zig-out/bin/read_vs_mmap read-file-pread --aligned build.random 16 100000':

                37      page-faults
                 1      major-faults
                36      minor-faults

      24.524290927 seconds time elapsed

       0.016676000 seconds user
       1.359095000 seconds sys


anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1577120     4733200       96800     2122592     6679344
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo perf stat -e page-faults,major-faults,minor-faults   ./zig-out/bin/read_vs_mmap read-file-mmap --aligned build.random 16 100000

 Performance counter stats for './zig-out/bin/read_vs_mmap read-file-mmap --aligned build.random 16 100000':

            83,056      page-faults
            83,020      major-faults
                36      minor-faults

      24.766600640 seconds time elapsed

       0.240115000 seconds user
       1.213217000 seconds sys


anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1525808     4767376       96800     2139776     6730656
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo perf stat -e context-switches   ./zig-out/bin/read_vs_mmap read-file-mmap --aligned build.random 16 100000

 Performance counter stats for './zig-out/bin/read_vs_mmap read-file-mmap --aligned build.random 16 100000':

            83,491      context-switches

      24.336124402 seconds time elapsed

       0.250663000 seconds user
       1.165584000 seconds sys


anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1573984     4730960       96800     2127968     6682480
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo perf stat -e context-switches   ./zig-out/bin/read_vs_mmap read-file-pread --aligned build.random 16 100000

 Performance counter stats for './zig-out/bin/read_vs_mmap read-file-pread --aligned build.random 16 100000':

            83,649      context-switches

      24.343639919 seconds time elapsed

       0.012542000 seconds user
       1.329475000 seconds sys


anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1537088     4766352       96832     2129456     6719376
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo perf stat -e context-switches   ./zig-out/bin/read_vs_mmap read-file-mmap build.random 16 100000

 Performance counter stats for './zig-out/bin/read_vs_mmap read-file-mmap build.random 16 100000':

           140,288      context-switches

      39.316094776 seconds time elapsed

       0.240258000 seconds user
       2.018173000 seconds sys


anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1551296     3834464       96800     3047184     6705168
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo perf stat -e context-switches   ./zig-out/bin/read_vs_mmap read-file-pread build.random 16 100000

 Performance counter stats for './zig-out/bin/read_vs_mmap read-file-pread build.random 16 100000':

            81,175      context-switches

      35.147318162 seconds time elapsed

       0.012514000 seconds user
       1.539323000 seconds sys


anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo sh -c 'free && sync && echo 3 >/proc/sys/vm/drop_caches'
               total        used        free      shared  buff/cache   available
Mem:         8256464     1532544     3865760       96800     3034608     6723920
Swap:        2097136           0     2097136
anubhav@rpi1:~/Desktop/learning/read_vs_mmap $ sudo perf stat -e page-faults,major-faults,minor-faults   ./zig-out/bin/read_vs_mmap read-file-mmap --aligned build.random 16 100000

 Performance counter stats for './zig-out/bin/read_vs_mmap read-file-mmap --aligned build.random 16 100000':

            83,217      page-faults
            83,182      major-faults
                35      minor-faults

      24.230830406 seconds time elapsed

       0.274217000 seconds user
       1.189906000 seconds sys
```
