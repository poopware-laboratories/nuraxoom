# grate Mesa for Phosh on the Tegra 2 GPU

[grate's Mesa](https://github.com/grate-driver/mesa) (Gallium driver
`grate`) with NuraXoom's patches, so that phoc, Phosh's compositor, can draw
with wlroots' GLES2 renderer on the Xoom's GPU instead of in software.

Experimental: it isn't in the images yet, and only phoc uses it. Phosh and
apps keep drawing with cairo (`GSK_RENDERER=cairo`), as before.

## Patches

| Patch | What |
|---|---|
| 0001 | Configure with Python 3.12 (no `distutils`) |
| 0002 | Share buffers as dma-buf (phoc's scanout buffers, Wayland EGL clients) |
| 0003 | Make 3D draws render on the upstream kernel: vertex shader constants, draw offsets, depth function, no-depth render targets, opentegra's state reset, no bottom-up buffers |
| 0004 | Textures, blending and hand-written programs for wlroots' fragment shaders (`fp/wlr/*.asm`) |
| 0005 | `GRATE_DUMP=1` prints each job's command stream |
| 0006 | Don't write Tegra114 registers on Tegra20: the 3D unit stalled ~1 s per job on them |
| 0007 | Scissor (wlroots redraws only damaged regions) |
| 0008 | Batch a frame's draws into one GPU job |
| 0009 | `GRATE_TIME=1` prints submit and wait time per job |
| 0010 | One-pass blending programs (full-screen blend 18 → 8.5 ms), RGBX programs |
| 0011 | Don't keep freed buffers over 1 MB in grate's buffer cache (CMA) |

grate's own fragment compiler only handles `MOV`. Patch 0004 doesn't extend
it: it recognises wlroots' three fragment shaders (solid colour, texture ×
alpha, RGBX texture × alpha) and runs fixed Tegra programs for them. Other
GL programs won't draw correctly.

## Files

- `build.sh`: fetch the pinned grate commit, apply the patches, build for
  armv7 VFPv3-D16 and pack `/opt/mesa-grate` as a tarball.
- `gen-wlr-fp.sh`: regenerate `fp/wlr/wlr_programs.h` from the `.asm` files
  with xf86-video-opentegra's assembler (only needed after editing them).
- `phoc-gpu`: start phoc with grate's Mesa and `WLR_RENDERER=gles2`; the
  session it starts gets the normal environment, and if phoc fails on the GPU
  within 15 s it runs again with the software renderer.
- `gltest.c`: headless GLES2 check with wlroots' shaders; prints the pixels it
  reads back. `gltest /dev/dri/card0 upload` also times full-screen texture
  uploads and compositing (1280x800: upload ~9 ms, copy ~5.4 ms, blended
  ~8.5 ms).

## Trying it

```sh
doas tar -xzf mesa-grate-armv7.tar.gz -C /
doas install -m755 phoc-gpu /usr/libexec/nuraxoom/phoc-gpu
echo COMPOSITOR=/usr/libexec/nuraxoom/phoc-gpu > ~/.phoshdebug
```

`phosh-session` sources `~/.phoshdebug`; delete it to go back to software
phoc.

## Known issues

- phoc waits for the GPU at the end of every frame (no fences yet), so the
  CPU and the GPU don't overlap.
- GPU memory (CMA, 256 MB): a running Phosh uses ~86 MB. Each phoc session
  leaves ~8 MB allocated in the kernel when it exits (about two screen
  buffers), so restarting Phosh many times without rebooting runs it out.
