# Maid2

A OOP cleanup manager like Janitor, Maid, Trove and Dumpster but **much** faster and lighter.

Uses SOME types from Trove, not everything

## Benchmark

Tested using Scriptbench (1000 tests ran with 10000 blank functions)

| Library | Total Time | Add Time | Clean Time |
| :--- | :--- | :--- | :--- |
| **IExplodeU** | `1491 ps` | `1091 ps` | `374 ps` |
| **Fang** | `1568 ps` | `1105 ps` | `416 ps` |
| **Maid** | `1580 ps` | `1134 ps` | `404 ps` |
| **Cleaner** | `1587 ps` | `1157 ps` | `374 ps` |
| **Warden** | `1719 ps` | `1029 ps` | `636 ps` |
| **Job** | `2223 ps` | `1111 ps` | `1054 ps` |
| **DarkScythe** | `2669 ps` | `1946 ps` | `694 ps` |

[IExplodeU](https://github.com/realllityyy/IExplodeU)