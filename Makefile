SHELL=/bin/bash

all: node_modules dist data/gschemas.compiled gtk-hypermd

node_modules:
	npm install

dist: .PHONY
	rm -rf dist
	$$(npm bin)/parcel build --no-minify --out-dir=dist --public-url="/dist/" html/edit.html

data/gschemas.compiled: data/me.ivank.gtk-hypermd.gschema.xml
	rm -f data/gschemas.compiled
	glib-compile-schemas data

clean:
	rm -rf dist data/gschemas.compiled python/gtkhypermd/__pycache__ __pycache__ .cache

distclean: clean
	rm -rf node_modules package-lock.json

gtk-hypermd: .PHONY
	cd vala && \
	rm -f *.c && \
	glib-compile-resources gresource.xml --generate-source --target=gresource.c && \
	valac \
	  -o ../gtk-hypermd \
	  -g \
	  --enable-checking \
	  --gresources gresource.xml \
	  --pkg gio-2.0 \
	  --pkg granite \
	  --pkg gtk+-3.0 \
	  --pkg json-glib-1.0 \
	  --pkg libsoup-2.4 \
	  --pkg posix \
	  --pkg webkit2gtk-4.0 \
	  --Xcc=-Wno-deprecated-declarations \
	  *.vala gresource.c && \
	rm -f gresource.c

.PHONY:
