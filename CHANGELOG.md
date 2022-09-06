<a name="0.3.0"></a>
## [0.3.0](https://github.com/graph-guard/ggproxy/compare/0.2.0...0.3.0) (2022-09-06)

### Feat

* Allow submatching - any set of matching fields and valid arguments are allowed to pass. The code snippet below shows a short example:
    ```
    ## gqt
    query {
        a(
            a_0: val = 0
            a_1: val = 1
        ) {
            a0
            a1
        }
    }

    ## gql
    query {
        a(
            a_0: 0
        ) {
            a0
        }
    }

    ## PASSED
    ```

* Add `combine N { ... }` blocks. These blocks allow to make combinations of **up to N** fields. Instead of defining many templates, they can be combined sometimes:
    ```
    query {
        combine 2 {
            a
            b
            c
        }
    }

    ### Replaces 3 separate templates
    ```

### Fix

* Fix panic in API match field on subsequent requests
* Fix shell broken pipe handling

<a name="0.2.0"></a>
## 0.2.0 (2022-08-29)

### Feat

* Add inline fragments suppot

<a name="0.1.0"></a>
## 0.1.0 (2022-08-26)

### Feat

* Initial release

