# mapsy
A maps TUI program.
 See the go-staticmaps project for the original inspiration.
 Significant code was ported to Zig from the original Go source.


## Quickstart
1. Obtain dependencies: `nix develop`
2. Build binary exe: `zig build`
3. Create app dir: `mkdir $HOME/Library/Application\ Support/mapsy`
4. Run program: `zig-out/bin/mapsy`


## Credits
Go-staticmaps
  by [Florian Pigorsch](https://github.com/flopp/go-staticmaps) ([LICENSE](https://github.com/flopp/go-staticmaps/blob/master/LICENSE))

Cairo binding 
  by [koenigskraut](https://github.com/koenigskraut/giza)

libvaxis examples
  by [Tim Culverhouse](https://github.com/rockorager/libvaxis) ([LICENSE](https://github.com/rockorager/libvaxis/blob/master/LICENSE))

HTTP fetch
  by [Ziggit forums](https://ziggit.dev/t/what-is-the-simplest-way-to-send-a-one-shot-http-request-in-zig-to-a-known-address/8490/2)

S2 geometry library

OSM raster tiles


