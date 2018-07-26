# 1st argument: a directory
# Call this script in the folder that contains LibDeflate.lua
# Record all small files in the directory and its subdir in a list
# and continues to randomly pick up a file from the list.
# And run lua test file on the file.
# If fails, abort and show the file name

import os
import sys
import random

fileList = []
def traverse(rootDir):
    for root, dirs, files in os.walk(rootDir):
        for file in files:
            try:
                if file.find("compress") == -1 \
                    and file.find(".lnk") == -1 and os.path.getsize(os.path.join(root, file)) <= 1024*1024:
                    fileList.append(os.path.join(root, file))
            except WindowsError:
                pass # Wierd pass
        for dir in dirs:
            traverse(dir)

if __name__ == '__main__':
    traverse(sys.argv[1])
    print("File list has been generated. Start testing")
    while True:
        rand = random.randint(0, len(fileList)-1)
        file = fileList[rand]
        try:
            f=open(file, "rb")
            f.close()
            ret = os.system("luajit tests\\Test.lua -o "+file)
            if ret == 0: # Lua can open the file.
                ret = os.system("luajit tests\\Test.lua -c "+file+" tests\\tmp.compressed")
                if ret == 0:
                    print(file, "OK")
                else:
                    print(file, "ERRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRROR")
                    exit(1)
        except Exception as e:
            print("Python cannot open:", file)

