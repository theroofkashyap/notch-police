.PHONY: build release test icon bundle run demo clean

build:
	chmod +x Scripts/*.sh Scripts/*.py
	./Scripts/build.sh debug

release:
	chmod +x Scripts/*.sh Scripts/*.py
	./Scripts/build.sh release

test:
	chmod +x Scripts/*.sh Scripts/*.py
	./Scripts/test.sh

# AppIcon.icns is committed, so a normal build needs no image tooling. Run
# this after editing Resources/AppIcon.png; it needs Pillow and numpy.
icon:
	python3 Scripts/generate-icon.py

bundle: build
	./Scripts/bundle.sh debug

run: bundle
	pkill -x NotchPolice || true
	sleep 0.3
	open -n .build/NotchPolice.app

demo: bundle
	pkill -x NotchPolice || true
	sleep 0.3
	open --env NOTCH_POLICE_DEMO=1 -n .build/NotchPolice.app

clean:
	rm -rf .build
