# DemoApp

The project's own README: say what it is here. Doxygen uses this file as the documentation's main page.

The build system is the Breeze template, in [`breeze/`](breeze/README.md); this project's settings are
in [`project/Configuration.cmake`](project/Configuration.cmake).

```sh
breeze/scripts/setup.sh                  # once per clone; asks before installing anything
breeze/scripts/build.sh                  # configure and build (Release)
breeze/scripts/run.sh hello_exe World    # run a module
```

On Windows use `breeze\scripts\setup.bat`, `breeze\scripts\build.bat` and `breeze\scripts\run.bat`.
