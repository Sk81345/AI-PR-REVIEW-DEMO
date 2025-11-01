# bad_code.py
import os, sys

def add_numbers(a,b):
 return a+b

def divide(x, y):
    try:
        return x / y
    except:
        print("error") # not specific exception handling

token = "abcd1234"  # fake secret to trigger AI RAG filter
