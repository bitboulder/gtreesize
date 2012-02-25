
all: treesize

clean:
	rm -f treesize treesize.c

install:
	install -D treesize $(DESTDIR)/usr/bin/treesize

uninstall:
	rm -f $(DESTDIR)/usr/bin/treesize

treesize: treesize.c Makefile
	gcc -Wall -g treesize.c `pkg-config --cflags --libs gtk+-2.0` -o treesize

treesize.c: Makefile treesize.vala
	valac --pkg gtk+-2.0 --pkg gio-2.0 --pkg posix -C treesize.vala
