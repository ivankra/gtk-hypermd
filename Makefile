all: node_modules data/dist data/gschemas.compiled

node_modules:
	npm install

data/dist: .PHONY
	rm -rf data/dist
	$$(npm bin)/parcel build --out-dir=data/dist --public-url="app://data/dist/" html/edit.html

data/gschemas.compiled: data/me.ivank.gtk-hypermd.gschema.xml
	rm -f data/gschemas.compiled
	glib-compile-schemas data

clean:
	rm -rf data/dist data/gschemas.compiled python/gtkhypermd/__pycache__ __pycache__ .cache

distclean: clean
	rm -rf node_modules package-lock.json

.PHONY:
