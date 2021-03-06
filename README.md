[![Donate](https://img.shields.io/badge/PayPal-Donate%20to%20Author-blue.svg)](https://www.paypal.me/emanuele42)
[![OpenStore](https://img.shields.io/badge/Install%20from-OpenStore-000000.svg)](https://open-store.io/app/sturmreader.emanuelesorce)

Ebook Reader for Linux
=======================
Sturm reader is an ebook reader for Linux.  It's built now for Ubuntu Touch.
It has features to style the book.
It features full support for Epub files and preliminary support for PDF and CBZ files.

It's a fork of Beru from Rschroll (http://rschroll.github.io/beru), thanks!

Building
--------
To build for the system you are working on, do
```
$ mkdir <build directory>
$ cd <build directory>
$ cmake <path to source>
$ make
```

To build the click for an Ubuntu Touch device and create a .click package, you can just use clickable
```
$ clickable
```

Running
-------
Launch Sturm Reader with the shell script `sturmreader`.

Sturm Reader keeps a library of epub files.  On every start, a specified folder
is searched and all epubs in it are included in the library.  You may
also pass a epub file as an argument.  This will open the file
and add it to your library.

The Library is stored in a local database.  While I won't be
cavalier about changing the database format, it may happen.  If
you're getting database errors after upgrading, delete the database
and reload your files.  The database is one of the ones in
`~/.local/share/sturmreader.emanuelesorce/Databases`;
read the `.ini` files to find the one with `Name=BeruLocalBooks`.


Known Problems
--------------
Known bugs are listed on the [issue tracker][1].  If you don't see
your problem listed there, please add it!

[1]: https://github.com/tronfortytwo/sturmreader/issues "Bug tracker"
