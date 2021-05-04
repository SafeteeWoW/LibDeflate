#!/usr/bin/env python3
"""
Test using random files in disk.

1st argument: a directory

Call this script in the folder that contains LibDeflate.lua

Record all small files in the directory and its subdir in a list
and continues to randomly pick up a file from the list.
And run lua test file on the file.
If fails, abort and show the file name
"""

import os
import sys
import random

fileList = []


def traverse(rootDir):
    for root, dirs, files in os.walk(rootDir):
        for file in files:
            try:
                if file.find("compress") == -1 \
                    and file.find(".lnk") == -1 \
                    and os.path.getsize(os.path.join(root, file)) <= 1024*1024:
                    fileList.append(os.path.join(root, file))
            except OSError:
                pass  # Wierd pass
        for dir in dirs:
            traverse(dir)


def main():
    traverse(sys.argv[1])
    random.shuffle(fileList)
    print("File list has been generated. Start testing")
    for file in fileList:
        try:
            f = open(file, "rb")
            f.close()
            ret = os.system("luajit tests/Test.lua -o " + file)
            if ret == 0:  # Lua can open the file.
                print("Testing file " + file)
                ret = os.system("luajit tests/Test.lua -c " + file +
                                " tests/tmp.compressed")
                if ret == 0:
                    print(file, "OK")
                else:
                    print(file,
                          "ERROR: Exit code is " + str(ret),
                          file=sys.stderr)
                    exit(ret)
        except Exception as e:
            print("WARNING: Python cannot open:", file, file=sys.stderr)


if __name__ == '__main__':
    main()
