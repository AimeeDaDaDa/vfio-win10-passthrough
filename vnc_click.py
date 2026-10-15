#!/usr/bin/env python3
"""VNC 精确点击工具: vnc_click.py click X Y | move X Y | dblclick X Y"""
import socket, struct, sys

HOST, PORT = "127.0.0.1", 5900

def connect():
    s = socket.create_connection((HOST, PORT), timeout=5)
    ver = s.recv(12)                      # server version
    s.sendall(b"RFB 003.008\n")
    n = s.recv(1)[0]                      # security type count
    types = s.recv(n)
    assert 1 in types, f"无 None 认证: {list(types)}"
    s.sendall(b"\x01")                    # 选 None
    assert struct.unpack(">I", s.recv(4))[0] == 0, "认证失败"
    s.sendall(b"\x01")                    # ClientInit: shared
    s.recv(24)                            # ServerInit (含宽高/名字)
    return s, ver

def pointer(s, x, y, mask=0):
    # 坐标系 0..65535
    s.sendall(struct.pack(">BBHHH", 5, mask, x, y, 0))

def click(s, gx, gy, gw=1080, gh=675, double=False):
    x = int(gx / gw * 65535); y = int(gy / gh * 65535)
    pointer(s, x, y, 0); 
    for _ in range(2 if double else 1):
        pointer(s, x, y, 1); 
        import time; time.sleep(0.06)
        pointer(s, x, y, 0); time.sleep(0.06)

def main():
    cmd = sys.argv[1]
    s, _ = connect()
    import time
    if cmd == "click":
        click(s, int(sys.argv[2]), int(sys.argv[3]))
    elif cmd == "move":
        pointer(s, int(int(sys.argv[2])/1080*65535), int(int(sys.argv[3])/675*65535), 0)
    print("OK", flush=True)

if __name__ == "__main__":
    main()
