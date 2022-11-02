#!/bin/sh
. /root/gstreamer-examples/func.sh

init_dev
[ $? -ne 0 ] && exit 1

guess_param
setup-pipeline-csi1 -f $CAM_COL_FMT -s $SENSOR_RES -o $OFFSET_SENSOR -c $SENSOR_RES
$V4L2_CTRL_CAM1_COL

echo "========================================================================="
echo "starting gstreamer to push camera feed to rtsp"
echo "========================================================================="

RTSP_ENDPOINT=/phycam

gst-launch-1.0 \
    v4l2src device=$VID_DEVICE ! \
    video/x-$COL_FORMAT,$FRAME_SIZE ! \
    bayer2rgbneon ! \
    vpuenc_h264 ! \
    queue ! rtspclientsink location=rtsp://0.0.0.0:8554$RTSP_ENDPOINT

