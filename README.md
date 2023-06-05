## Instructions

To run the tests first install sunodo, then:

```shell
# install sunodo
npm install -g @sunodo/cli

# build the dapp
sunodo build

# run usual tests
docker run --rm -it -v `pwd`:/mnt -e LUA_PATH_5_3=";;/opt/cartesi/share/lua/5.3/?.lua" -e LUA_CPATH_5_3=";;/opt/cartesi/lib/lua/5.3/?.so" sunodo/sdk:0.15.0 \
    lua5.3 honeypot-usual-tests.lua

# run edge tests
docker run --rm -it -v `pwd`:/mnt -e LUA_PATH_5_3=";;/opt/cartesi/share/lua/5.3/?.lua" -e LUA_CPATH_5_3=";;/opt/cartesi/lib/lua/5.3/?.so" sunodo/sdk:0.15.0 \
    lua5.3 honeypot-edge-tests.lua
```
