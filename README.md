# Base ostree image

This repository contains a Fedora base [ostree][1] image that uses [bootc][2].
  - The resulting image is not a product suitable for downstream uses.
  - If you wish to use anything here, you are *on your own*.
  - Do not complain here if your data evaporates because you used this.

## Building

The image defined in this repo builds with github actions. Review the build workflow yaml for specifics. A script may be added in the future for testing builds outside of CI.

[1]: https://coreos.github.io/rpm-ostree/
[2]: https://github.com/containers/bootc
