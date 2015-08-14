#!/bin/sh

dir=`dirname "$(readlink -f "$0")"`

cp $dir/ovf* /usr/local/bin
chmod +x /usr/local/bin/ovf*

cp $dir/../lib/ovf*.service /usr/lib/systemd/system/
for f in $dir/../lib/ovf*.service; do
    systemctl enable `basename $f`
done
