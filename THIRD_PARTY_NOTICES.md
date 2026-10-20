# Third-party notices

SwiftDefaultApps is released under the Beerware license (see [LICENSE](LICENSE)). It includes, links or was built with the
following. Who wrote which file of SwiftDefaultApps itself is recorded in the Git history (`git log --follow -- <file>`).

## SwiftCLI

The `swda` command line tool links SwiftCLI as a static library. Its sources are the Git submodule `Packages/SwiftCLI-2.0.3`
(the fork <https://github.com/Lord-Kamina/SwiftCLI> of <https://github.com/jakeheis/SwiftCLI>), which keeps its own
`LICENSE`. It is released under the MIT license:

> The MIT License (MIT)
>
> Copyright (c) 2014 Jake Heiser
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all
> copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
> SOFTWARE.

## The icon

The icon (`Main Assets.xcassets`) was made from these resources, which ask for attribution:

- Brush, Ruler and Pencil designed by Freepik: <http://www.freepik.com/free-vector/background-of-back-to-school_769298.htm>
- Magnifying glass frame designed by Balintseby / Freepik: <http://www.freepik.com/free-vector/realistic-magnifying-glass_789215.htm>
- Magnifying glass crystal designed by Freepik: <http://www.freepik.com/free-vector/crystal-frames-collection_724172.htm>
- Gears designed by Freepik: <http://www.freepik.com/free-vector/gray-background-of-gear_956712.htm>

## No longer included

Earlier versions of the preference pane contained a canned-views system by AMTourky (DRYView), a `SynchronizedArray` from
ZamzamKit, and a few helpers adapted from ZamzamKit and SwifterSwift. None of that code is in the sources any more; it is in
the Git history only.
