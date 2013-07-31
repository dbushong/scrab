#!/usr/bin/env coffee

prog  = require 'commander'
prog.parse(process.argv)

fs   = require 'fs'
lazy = require 'lazy'

trie = {}

calc = (ptr, offs=0) ->
  ptr['.'] = (ptr['.'] || []).join()
  len = ptr['.'].length

  chars = (k for k of ptr when /^[a-z]$/.test k).sort()

  # answers len + answers + chars len + stop
  offs += 1 + len + 5 * chars.length + 1

  for char in chars
    ptr[char].off = offs
    offs = calc ptr[char], offs

  offs

zero = new Buffer('\0')
output = (fh, ptr, foo=false) ->
  # write out answers if this is a stop location
  len = ptr['.'].length
  buf = new Buffer(1)
  buf.writeUInt8(len, 0)
  fh.write(buf)
  fh.write(ptr['.'], 'ascii') if len

  chars = (k for k of ptr when /^[a-z]$/.test k).sort()

  for char in chars
    fh.write char, 'ascii'
    buf = new Buffer(4)
    buf.writeUInt32BE(ptr[char].off, 0)
    fh.write buf

  fh.write zero

  output(fh, ptr[char], true) for char in chars

addWord = (line) ->
  word    = line.toLowerCase()
  letters = word.split('').sort()
  ptr     = trie
  ptr     = ptr[char] ||= {} for char in letters
  (ptr['.'] ||= []).push word

console.log 'building %trie'
fh = fs.createReadStream prog.args[0]
lazy(fh).lines.map(String).forEach(addWord).on 'pipe', ->
  console.log 'calculating offsets'
  calc trie

  console.log 'writing data'
  fh = fs.createWriteStream('twl06.trie')
  output fh, trie
  fh.end()

###
coffee
00000000  00 61 00 00 00 81 00 00  61 00 00 00 81 00 00 61  |.a......a......a|
00000010  00 00 00 81 64 00 00 00  81 00 00 64 00 00 00 81  |....d......d....|
00000020  00 00 6b 00 00 00 81 00  00 72 00 00 00 81 00 00  |..k......r......|
00000030  72 00 00 00 81 00 00 73  00 00 00 81 76 00 00 00  |r......s....v...|
00000040  81 00 00 76 00 00 00 81  00 00 61 61 72 64 76 61  |...v......aardva|
00000050  72 6b 73 00 00 61 61 72  64 76 61 72 6b 00 00 66  |rks..aardvark..f|
00000060  00 00 00 81 00 00 6c 00  00 00 81 00 00 6f 00 00  |......l......o..|
00000070  00 81 00 00 72 00 00 00  81 00 00 77 00 00 00 81  |....r......w....|
00000080  00 00 61 61 72 64 77 6f  6c 66 00                 |..aardwolf.|
perl
00000000  00 61 00 00 00 07 00 00  61 00 00 00 0e 00 00 61  |.a......a......a|
00000010  00 00 00 1a 64 00 00 00  5e 00 00 64 00 00 00 21  |....d...^..d...!|
00000020  00 00 6b 00 00 00 28 00  00 72 00 00 00 2f 00 00  |..k...(..r.../..|
00000030  72 00 00 00 36 00 00 73  00 00 00 42 76 00 00 00  |r...6..s...Bv...|
00000040  54 00 00 76 00 00 00 49  00 09 61 61 72 64 76 61  |T..v...I..aardva|
00000050  72 6b 73 00 08 61 61 72  64 76 61 72 6b 00 00 66  |rks..aardvark..f|
00000060  00 00 00 65 00 00 6c 00  00 00 6c 00 00 6f 00 00  |...e..l...l..o..|
00000070  00 73 00 00 72 00 00 00  7a 00 00 77 00 00 00 81  |.s..r...z..w....|
00000080  00 08 61 61 72 64 77 6f  6c 66 00                 |..aardwolf.|
###
