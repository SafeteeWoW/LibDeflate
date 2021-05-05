# IDE Setup

This describes my IDE setup when I develop this addon.
Other develpers can use my setup as a reference.

## Operating System

Windows Subsystem for Linux v2 (Ubuntu 20.04 LTS)

## IDE

Visual Studio Code

## VSCode Plugins

1. vscode-lua (trixnz.vscode-lua): For Lua linting

2. Lua Debug (actboy168.lua-debug): Lua Debugger

   Note that the embeded lua of "Lua Debug" requires libreadline.so.6,
   which has no corresponding package in Ubuntu 20.04. Without this so,
   the debugging session will be stuck when you start debugging. Create a symlink to libreadline.8 solves the problem

   sudo ln -sf /usr/lib/x86_64-linux-gnu/libreadline.so.8 /usr/lib/x86_64-linux-gnu/libreadline.so.6

3. shell-format (foxundermoon.shell-format): Shell script format integration

4. Prettier - Code formatter (esbenp.prettier-vscode): Prettier code formatter integration

5. C/C++ (ms-vscode.cpptools): C/C++ IntelliSense

## Ubuntu packages

1. lua5.1

2. luajit

3. luarocks

4. Other packages described in other documents, including [format.md](format.md)

## Luarocks packages

Please read other documents for required Luarocks packages,
including [tests/README.md](../tests/README.md)
