
### before: stock 7.3.0-15 (370 cases)

| requested | cases | commit accepted | rejected (errno) | bus format = request | camera GOOD (of accepted) |
|---|---|---|---|---|---|
| AUTO | 74 | 74 | 0  | 74/74 | 74/74 |
| RGB | 74 | 74 | 0  | 74/74 | 74/74 |
| 444 | 74 | 74 | 0  | 0/74 | 74/74 |
| 422 | 74 | 74 | 0  | 0/74 | 74/74 |
| 420 | 74 | 74 | 0  | 0/74 | 74/74 |

### after: 15ycc1 (k15-dpycc) (370 cases)

| requested | cases | commit accepted | rejected (errno) | bus format = request | camera GOOD (of accepted) |
|---|---|---|---|---|---|
| AUTO | 74 | 74 | 0  | 74/74 | 74/74 |
| RGB | 74 | 74 | 0  | 74/74 | 74/74 |
| 444 | 74 | 74 | 0  | 74/74 | 74/74 |
| 422 | 74 | 74 | 0  | 74/74 | 74/74 |
| 420 | 74 | 0 | 74 22 | 0/0 | 0/0 |

### after: accepted cases that are not GOOD or not the requested format


cases in before but not after: 0 
