# phyCORE i.MX 8M Plus Guide
This is an internal guide that will help with setting up Nabto on phytec's i.MX 8M Plus SoM.

## Prerequisites
You can use `microcom` for serial connection to the board or another terminal/program capable of connecting to a serial port. The baudrate for the board is `115200`.

## Downloading and flashing an image to the SD card
Go to [phytec's product page](https://www.phytec.eu/en/produkte/system-on-modules/phycore-imx-8m-plus/?lang=en/#downloads/) to download an appropriate Board Support Package, listed under `Linux BSP-Releases using Yocto`. This guide will use the `Standard NXP BSP` release version [PD22.1.0](https://www.phytec.eu/en/bsp-download/?bsp=BSP-Yocto-NXP-i.MX8MP-PD22.1.0).

On this site you can check out the "Supported machines" section. Our board has article number `PB-03123-001.A1` so our corresponding machine name is `phyboard-pollux-imx8mp-3`.In the "Binaries" section you can find a link to prebuilt images which leads to: 
> <https://download.phytec.de/Software/Linux/BSP-Yocto-i.MX8MP/BSP-Yocto-NXP-i.MX8MP-PD22.1.0/images/>

The prebuilt image we will use is `ampliphy-vendor-xwayland` which has gstreamer and v4l2 already included. `ampliphy-vendor` is the stripped image that does not include any extra software, however using it would require us to build gstreamer from scratch, which is possible but out of scope for the guide.

The full path to the image we use is
> [ampliphy-vendor-xwayland/phyboard-pollux-imx8mp3/phytec-vision-image-phyboard-pollux-imx8mp-3.sdcard](https://download.phytec.de/Software/Linux/BSP-Yocto-i.MX8MP/BSP-Yocto-NXP-i.MX8MP-PD22.1.0/images/ampliphy-vendor-xwayland/phyboard-pollux-imx8mp-3/phytec-vision-image-phyboard-pollux-imx8mp-3.sdcard)

Flashing to the sd card can be done with `dd` as:
```sh
sudo dd if=phytec-vision-image-phyboard-pollux-imx8mp-3.sdcard of=/dev/mmcblk0 conv=fsync status=progress
```
When flashing is complete reinsert the SD card into the board and power it on.

## Connecting to the board
Using a USB connection and `microcom` we can connect to the board with
```sh
microcom -p /dev/ttyUSB0 -s 115200 
```
By default there is only the root user with no password.

## Enabling the camera using Linux Device Tree
Linux device tree is a data structure used to describe hardware components. Phytec provides some overlays that we can apply to the device tree to enable certain hardware such as a phytec camera. These overlays have a `.dtbo` extension and can be found in `/boot`

The file `/boot/bootenv.txt` describes which overlays should be applied to the device tree. We can refer to [this camera guide][1], which also describes how to connect the camera to the board. We'll use the `CSI1` port for this, which is also called `X11` in some parts of the documentation.

> NOTICE:
> We're using PD22.1.0 which has a slightly different approach to modifying the device tree compared to older versions.

In section 6 we can see which overlay files should be applied to enable the camera on CSI1. Note the article name of your camera, in our case it is `VM-016-COL-M-M12.A1` and it is connected to `X11`. This means we have to add the following overlays.
```
imx8mp-isi-csi1.dtbo imx8mp-vm016-csi1.dtbo
```
We use the following command to output the correct contents to `/boot/bootenv.txt`
```sh
echo "overlays=imx8mp-phyboard-pollux-peb-av-010.dtbo imx8mp-isi-csi1.dtbo imx8mp-vm016-csi1.dtbo" > /boot/bootenv.txt
```
Reboot the board and the camera should now be available for use. You can use `ls /dev` to check that there is a `/dev/video*` file (`/dev/video0` in our case).

## Installing required packages on the board
For the current Nabto setup we need three things on the board. The first is of course Nabto's TCP tunnel application, the second is `gst-rtsp-server` which provides the `rtspclientsink` command to gstreamer's pipelines, the third is `rtsp-simple-server` which we use to provide an RTSP endpoint.

For the PD22.1.0 image we downloaded, gstreamer 1.18.5 was included, so that is the version we need for `gst-rtsp-server`.

Next step is to download the [phytec-nabto.tar.gz](phytec-nabto.tar.gz?raw=1) tarball. This archive includes Nabto binaries such as `tcp_tunnel_device` and `thermostat_device`, and it also includes `gst-rtsp-server` version 1.18.5. Since the repository is private at the moment, you will have to use `scp` to copy the tarball over to the board from your computer. However, `wget` is available on the board for if this repository ever becomes public.

Connect the board with an ethernet cable and use `ip a` to find the ip address on the local network, then copy the tarball over.

```sh
scp phytec-nabto.tar.gz root@192.168.1.183:/root/phytec-nabto.tar.gz
```

Now, on the board, extract the tarball contents into `/usr`

```sh
tar xvf phytec-nabto.tar.gz -C /usr
```

Ensure that the installation succeeded by running the following two commands and inspecting the output.

```sh
tcp_tunnel_device --version
gst-inspect-1.0 --no-colors rtspclientsink
```

Finally we need to install [rtsp-simple-server](https://github.com/aler9/rtsp-simple-server/releases), thankfully they have ARM binaries on their github releases. Pick the `arm64v8` binary and download it onto the board using `wget`, then unpack the contents.

```sh
wget https://github.com/aler9/rtsp-simple-server/releases/download/v0.20.0/rtsp-simple-server_v0.20.0_linux_arm64v8.tar.gz
tar xvf rtsp-simple-server_v0.20.0_linux_arm64v8.tar.gz
```

## Starting up and testing an RTSP stream

We are now ready to start up an RTSP stream on the board and playing it on another computer on the local network. First start up `rtsp-simple-server` which will open a listener for an RTSP TCP stream on port 8554.
```sh
./rtsp-simple-server &
```
Then use gstreamer and `rtspclientsink` to push an RTSP stream to the server.
```sh
gst-launch-1.0 v4l2src device=/dev/video0 ! video/x-bayer,format=grbg,depth=8,width=1280,height=800 ! bayer2rgbneon ! queue ! vpuenc_hevc ! queue ! rtspclientsink location=rtsp://0.0.0.0:8554/phycam
```
The `/phycam` path can be replaced with whatever you'd prefer.

Note the `vpuenc_h264` part of the pipeline. This is a plugin for gstreamer that allows us to use the hardware encoder to encode into h264 format. You may use `vpuenc_hevc` if you prefer h265/HEVC over h264.

You can display the stream on a separate machine using `ffplay`.
```sh
ffplay -rtsp_transport tcp rtsp://192.168.1.183:8554/phycam
```

## TCP tunnelling with Nabto
Now we can simply initialize `tcp_tunnel_device` as we usually would with `--init`. Remember to add `rtsp-path` as a metadata entry with value `/phycam` (or whatever other path you decided on) to the rtsp server.

[1]: https://www.phytec.de/cdocuments/?doc=gADyHg#L1029e-A2phyCAMwithphyBOARDPolluxi-MX8MPlusGettingStartedGuide-HowtoChangetheDeviceTree
