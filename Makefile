
all: treesize

clean:
	rm -f treesize treesize.c

install:
	install -D treesize    $(DESTDIR)/usr/bin/treesize
	install -D treesize.pl $(DESTDIR)/usr/bin/treesize.pl

uninstall:
	rm -f $(DESTDIR)/usr/bin/treesize

treesize: treesize.c Makefile
	gcc -Wall -g treesize.c `pkg-config --cflags --libs gtk+-2.0 gee-1.0` -o treesize

treesize.c: Makefile treesize.vala
	valac --pkg gtk+-3.0 --pkg posix --pkg gee-1.0 -C treesize.vala
