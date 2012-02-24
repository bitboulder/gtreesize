treesize: treesize.c Makefile
	gcc -Wall -O2 -g treesize.c `pkg-config --cflags --libs gtk+-2.0` -o treesize

treesize.c: Makefile treesize.vala
	valac-0.12 --pkg gtk+-2.0 --pkg gio-2.0 --pkg posix -C treesize.vala
