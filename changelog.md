### v1.0.0-release

* 2018/7/30
* Documentation updates.

### v0.9.0-beta4

* 2018/5/25
* "DecodeForPrint" always remove prefixed or trailing control or space characters before decoding. This makes this API easier to use.

### v0.9.0-beta3

* 2018/5/23
* Fix an issue in "DecodeForPrint" that certain undecodable string
  could cause an Lua error.
* Add an parameter to "DecodeForPrint". If set, remove trailing spaces in the
input string before decode it.
* Add input type checks for all encode/decode functions.

### v0.9.0-beta2

* 2018/5/22
* API "Encode6Bit" is renamed to "EncodeForPrint"
* API "Decode6Bit" is renamed to "DecodeForPrint"

### v0.9.0-beta1

* 2018/5/22
* No change

### v0.9.0-alpha2

* 2018/5/21
* Remove API LibDeflate:VerifyDictionary
* Remove API LibDeflate:DictForWoW
* Changed API LibDeflate:CreateDictionary

### v0.9.0-alpha1

* 2018/5/20
* The first working version.
