from time import perf_counter
import socket

def check_dns(hostname):
    start = perf_counter()
    address = socket.gethostbyname(hostname)
    return address, round((perf_counter() - start) * 1000, 2)

print(check_dns("example.com"))
