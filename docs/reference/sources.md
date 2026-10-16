# Documentation sources and revisions

[Documentation index](../README.md)

Consolidated on **2026-10-16**. The appliance repository is the convenient home
for operator instructions. Kernel configuration and build scripts remain in
their respective repositories; check their actual contents when updating a
procedure. This review consolidates documentation and simplifies userspace
files; it does not include a new kernel build or phone deployment.

## AI usage

AI tools, including OpenAI Codex and ChatGPT, assisted with script changes,
documentation writing and consolidation, and hardware research. Imported
material retains the source attribution below. Completed checks and pending
device or electrical tests are recorded in the guides; see
[how to read validation claims](#how-to-read-validation-claims).

## Imported material

| Source snapshot | Material used |
| --- | --- |
| [Appliance scripts `103bb35`](https://github.com/BGW-10/klipper-android-appliance-scripts/tree/103bb35b74c1df99d8492381f66c7c9046c71174) | Debian/root/SSH setup, architecture, iw build, debloating, simplified boot scripts, and runit examples. |
| [Mona kernel `533a0b4f7464`](https://github.com/BGW-10/moto-g-stylus-2025-kernel/tree/533a0b4f7464bcf06a07b5097922fcb6748b9ded/docs/mona) | Image/config recipe, fake SOC, dated phone observations, performance, XL4015/USB protection, and hardware buying/cover guide. |
| [OnePlus kernel `e1d4edd7`](https://github.com/BGW-10/android_kernel_oneplus_msm8998/tree/e1d4edd7e05dabd32a9b8458d3b3c570cd992ba9) | `docs/BUILD_INSTALL.md`, `docs/MAINTAINER_SETUP.md`, actual `scripts/build.sh`, `scripts/setup-toolchains.sh`, `toolchains.conf`, and device defconfig. |

The OnePlus repository was cloned beside the other two using SSH, with a shallow
sparse checkout of docs, scripts, and ARM64 configs for this review. Its two
Markdown guides were byte-identical to the old appliance copies. The new local
guides consolidate them and correct the GCC pinning claim against the real
script, which clones branches without checking out its recorded hashes.
Both branch tips matched those hashes when checked on 2026-10-16; the explicit
checkout steps keep the build pinned if the branches later advance.

Mona source paths in copied guides now link to the inspected kernel revision.
Host examples use `~/phone-appliance` rather than a developer's absolute path.
The current script behavior supersedes older proposals for custom lifecycle,
charging polling, or a separate Wi-Fi boot script.

Services use root and `/root`. The former `examples/` files have been removed:
charging inhibition is now in `android/data/adb/service.d/`, disabled by default,
and printer application services are left for the operator to add. Three
Android scripts share `android/data/adb/appliance/common.sh` for the boot wait.

## Kernel fork documentation

The maintained device guides live in this repository. The duplicated guides
were removed from the kernel review branches, whose READMEs link here:

| Repository | Review branch | Based on |
| --- | --- | --- |
| Appliance scripts and documentation | `mona-appliance` | `main` |
| Moto kernel | `mona-appliance` | `mona-android16` |
| OnePlus kernel | `appliance-docs` | `usb-serial-enable` |

Kernel sources, configuration, and build tools stay in their kernel forks.
The original guides remain available in the pinned source snapshots above.

| Removed kernel page | Maintained guide |
| --- | --- |
| Mona `docs/mona/README.md` | [Mona index](../devices/mona/README.md) |
| Mona `docs/mona/building.md` | [Kernel build](../devices/mona/kernel.md) |
| Mona `docs/mona/fake-soc.md` | [Manual fake SOC](../devices/mona/fake-soc.md) |
| Mona `docs/mona/appliance.md` | [Power](../devices/mona/power.md), [performance](../devices/mona/performance.md), [validation](../devices/mona/validation.md) |
| Mona `docs/mona/usb-power.md` | [USB-C protection](../devices/mona/usb-power.md) |
| Mona `docs/mona/hardware.md` | [Hardware and printed cover](../devices/mona/hardware.md) |
| OnePlus `docs/BUILD_INSTALL.md` | [Kernel build and recovery](../devices/oneplus5/kernel.md) |
| OnePlus `docs/MAINTAINER_SETUP.md` | [Kernel maintenance](../devices/oneplus5/kernel-maintenance.md) |

## Old appliance page locations

| Previous appliance page | Current guide |
| --- | --- |
| `root-lineageos-debian-guide.md` | [OnePlus ROM/root](../devices/oneplus5/lineageos-root.md), [Debian](../setup/debian.md), [boot scripts](../setup/boot-services.md) |
| `debian-architecture-explained.md` | [Architecture](../architecture.md) |
| `kernel-build-guide.md` | [OnePlus kernel build/recovery](../devices/oneplus5/kernel.md) |
| `kernel-modification-maintainer-guide.md` | [OnePlus kernel maintenance](../devices/oneplus5/kernel-maintenance.md) |
| `aosp-iw-android-build-guide.md` | [Android iw](../android/iw.md) |
| `android-debloat.md` | [Android package trimming](../android/debloat.md) |
| `mona-appliance.md` | [Shared boot scripts](../setup/boot-services.md), [Mona](../devices/mona/README.md) |
| `runit.md` | [Service management](../services/runit.md) |

Two small compatibility pages remain at `mona-appliance.md` and `runit.md` for
existing links. Full historical text remains in the source snapshots above;
it is not a second installation path in the current docs.

## How to read validation claims

- **Observed:** a dated phone/source result carried from the investigation.
- **Host-checked:** shell syntax, links, temporary boot-helper checks, or the
  earlier runit exercise.
- **Pending:** a procedure or hardware recommendation requiring actual device,
  application, build, or electrical validation.

[Mona's validation page](../devices/mona/validation.md) records its specific
state. The OnePlus guides do not establish a newly tested firmware/kernel pair.
The hardware guide ranks module families using manufacturer specifications.
Search terms are buying aids; they do not verify a seller's board, availability,
or suitability. Electrical qualification on Mona remains pending.
