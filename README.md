# libfprint patch for the Elan 04f3:0903 fingerprint sensor

Makes the Elan `04f3:0903` fingerprint reader work on Linux, where stock
libfprint lists it as supported but cannot enroll with it:

```
$ fprintd-enroll
Enroll result: enroll-disconnected
```

The patch is against [libfprint](https://gitlab.freedesktop.org/libfprint/libfprint)
v1.94.100. **It is experimental, has not been reviewed by the libfprint
maintainers, and is weaker than a normal fingerprint reader. Read
[Security](#security) before using it.**

## Do you have this sensor?

```
$ lsusb -d 04f3:0903
Bus 001 Device 002: ID 04f3:0903 Elan Microelectronics Corp. ELAN:Fingerprint
```

Tested on one machine only: ASUS Vivobook M1503QA, Fedora 44, sensor firmware
`0x0170`, which reports an 80x80 sensor. Other `0903` units may differ. In
particular, the match threshold was chosen from this unit's 80x80 images.

## Install

You need systemd and `fprintd`, plus these to build (package names vary by distro):

- `git`, C and C++ compilers, `pkg-config`, `python3`
- `meson` 0.62 or newer, `ninja`
- Development files for `glib-2.0` (2.68 or newer), `gusb` and
  `gobject-introspection`

Then:

```
./install.sh
fprintd-delete "$USER"
fprintd-enroll -f right-index-finger
fprintd-verify
```

The script should work on any systemd distro, but has not been tried outside
Fedora. To use fingerprints for `sudo` and login, enable your distro's
`pam_fprintd` support as you normally would.

It builds into `/opt/libfprint-elan0903` and adds a systemd override so that
`fprintd` loads that copy. System packages are untouched, so package updates
will not overwrite it, and it also will not pick up upstream fixes. The build
contains only the Elan driver.

**Enrolling.** Press flat so the finger covers the sensor, hold still for about
a second, lift, and shift a little each time. Do not swipe, even though `fprintd`
describes the sensor as a swipe type and may report `swipe-too-short` (which here
means the press was too brief). Enrollment takes 12 presses.

If PAM fingerprint authentication is already enabled (on Fedora, check with
`authselect current` for `with-fingerprint`), the finger works for `sudo` and
login as soon as it is enrolled.

## Uninstall

```
./uninstall.sh
```

## Security

This matcher compares images directly, instead of the minutiae comparison
libfprint normally uses. Treat it as a convenience, not as strong protection.

- **Little test data.** The results below come from one person's fingers. It has
  not been tested against other people's fingers, so the false accept rate is
  unknown.
- **No liveness detection.** Nothing distinguishes a live finger from a copy.
- **Enrolled images are stored as is.** Prints in `/var/lib/fprint` contain
  fingerprint images rather than extracted features. Only root can read them,
  but anyone with root, or an unencrypted copy of the disk, can.
- **Not reviewed.** The matching code has had no independent review.

## What was wrong

Four separate problems stopped this sensor from working:

1. **Crash on "not ready" replies.** While waiting for a finger the sensor can
   reply `0xaf` or `0x00`, and the driver treated that as a protocol error. This
   is the `enroll-disconnected` above. Upstream already retries on these for
   `0c58`; the patch does the same for this sensor.
2. **Calibrating against the finger.** The driver recalibrates within about 50 ms
   of a capture, often with the finger still down, which shifted the baseline and
   spoiled later images. It now waits up to 2 seconds for the reading to settle.
3. **Treated as a swipe sensor.** The driver stitches frames together as a finger
   moves, and crops them to 50 rows to help. On this area sensor that produced
   images from 68 to 1081 rows tall. It now keeps all 80 rows and uses the sharpest
   frame of a press.
4. **Too few minutiae.** An 80x80 image has only 0-4 minutiae, so the standard
   matcher scored 0 on every comparison, including the same finger. The patch
   stores images and compares them by normalized cross-correlation, allowing for
   shifts of up to 20 pixels. A press must score 0.70 against an enrolled image.

All of this is limited to `0903`. The image matcher is a new path in shared code
(`fpi-image-device.c` and `fpi-print.c`), but it only runs for a device that opts
in, so other sensors keep their existing behavior.

## Test results

Single session, 12-press enrollment, right index finger enrolled, on a test build
that, for this sensor, differed from this patch only in debug logging and image
dumping:

| Finger | Presses | Result | Score |
|---|---|---|---|
| Right index (enrolled) | 10 | 10 matched | 0.926-0.967 |
| Left index, right middle, right ring, both thumbs | 15 | 15 rejected | 0.09-0.32 |

Presses tend to score lower when they are further removed from the enrollment.
Comparing images offline against an enrollment made a few minutes earlier gave
0.60-0.88 for the enrolled finger and up to 0.54 for other fingers, so that gap is
much narrower. Long-term reliability has not been measured. If matches start
failing, re-enroll rather than lowering the threshold.

## License

LGPL-2.1-or-later, the same as libfprint. See [LICENSE](LICENSE).
