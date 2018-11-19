all: node_modules dist data/gschemas.compiled

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

.PHONY:
