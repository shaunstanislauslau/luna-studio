#!/usr/bin/python
import os.path
import sys
from subprocess import call, Popen, PIPE


dir = os.path.join(os.path.dirname(os.path.realpath(__file__)), '..')
third_party = os.path.join(dir, 'third-party')
p_thrift   = os.path.join(third_party,  'thrift-0.9')
p_missingh = os.path.join(third_party,  'MissingH-1.2.0.0-winpatch')


def check(name):
    print "Checking if '%s' is installed" % name
    (out, err) = Popen(name, stdout=PIPE, shell=True).communicate()
    if not out:
        print "Please install '%s' to continue" % name
        sys.exit()  

check('cabal-dev')

print "Updateing cabal package cache"
if call(['cabal-dev', 'update']):
    print "ERROR"
    sys.exit()


print "Registering thrift library"
if call(['cabal-dev', 'add-source', p_thrift]):
    print "ERROR"
    sys.exit()
	

print "Registering MissingH library (to work on windows)"
if call(['cabal-dev', 'add-source', p_missingh]):
    print "ERROR"
    sys.exit()