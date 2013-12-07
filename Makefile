# Package: treesize
# Author:  Frank Duckhorn
#
# Copyright (c) 2013 Frank Duckhorn
#
# treesize is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free
# Software Foundation, either version 2 of the License, or (at your option)
# any later version.
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

VFLAGS=--pkg gtk+-3.0 --pkg posix
CFLAGS=-O2 -Wall -Wno-unused -g -c `pkg-config --cflags gtk+-3.0`
LFLAGS=`pkg-config --libs gtk+-3.0`

all: treesize

clean:
	rm -f treesize treesize.c

install:
	install -D treesize    $(DESTDIR)/usr/bin/treesize

uninstall:
	rm -f $(DESTDIR)/usr/bin/treesize

%: %.o Makefile
	gcc $(LFLAGS) $*.o -o $*

%.o: %.c Makefile
	gcc $(CFLAGS) $*.c -o $*.o

%.c: %.vala Makefile
	valac $(VFLAGS) -C $*.vala
