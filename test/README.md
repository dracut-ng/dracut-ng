The "Dracut Developer Guidelines" page in the main documentation has a
section that explains how to use these tests:
https://dracut-ng.github.io/dracut-ng/developer/hacking.html#_testsuite

The sources of that documentation are located in the
[doc_site/](/doc_site) folder at the top-level of this repository.

To find what tests are run by GitHub CI and in which configurations,
this is not a bad starting point:

   git grep -C 5 test/ -- .github/workflows/
