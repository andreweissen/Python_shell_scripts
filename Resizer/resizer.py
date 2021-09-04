#!/usr/bin/env python

"""
This Python shell script/module is used to resize images belonging to a number
of permissible file extension types and create new versions in the present
directory under new names for ease of access. The author includes the script in
his Pictures folder and invokes it in the Git Bash shell.
"""

__all__ = ["Resizer", "log_msg"]
__author__ = "Andrew Eissen"
__version__ = "1.0"

import PIL.Image
import sys


class Resizer:
    def __init__(self, data, extensions=None):
        """
        The ``Resizer`` class abstracts and compartmentalizes all the
        application logic responsible for undertaking the image resizing
        operation. The constructor takes a pair of arguments, namely, a list of
        file paths and resize factors and a list of permissible extensions.
            :param data: A list of file paths to images and resize factors by
                which to multiply the images' present dimensions
            :param extensions: An optional list of permissible file extensions,
                such as ``png`` and ``jpg``.
        """

        self.extensions = extensions
        self.data = data

    @property
    def extensions(self):
        """
        This function serves as the primary property "getter" function used to
        externally access the ``extensions`` instance attribute. It simply
        returns the value of the attribute in question.
            :return: The internal "private" object attribute endemic to the
                class instance
        """

        return self._extensions

    @extensions.setter
    def extensions(self, value):
        """
        This function serves as the primary property "setter" function used to
        externally set/reset new values for the ``extensions`` instance
        attribute. It simply applies the new value to the attribute in question.
        If the supplied value is ``None``, a default new list of permissible
        extensions is created and applied as the value.
            :param value: The value to be applied to the "private" class
                instance attribute
            :return: None
        """

        if value is None:
            value = ["jpg", "png"]
        self._extensions = value

    @property
    def data(self):
        """
        This function serves as the primary property "getter" function used to
        externally access the ``data`` instance attribute. It simply returns
        the value of the attribute in question.
            :return: The internal "private" object attribute endemic to the
                class instance
        """

        return self._data

    @data.setter
    def data(self, value):
        """
        This function serves as the primary property "setter" function used to
        externally set/reset new values for the ``data`` instance attribute. It
        simply applies the new value to the attribute in question, calling the
        private ``_format_input`` helper function to format the input.
            :param value: The value to be applied to the "private" class
                instance attribute
            :return: None
        """

        self._data = self._format_input(value)

    @staticmethod
    def _format_filename(file, ext, width, height):
        """
        The static private function ``_format_filename`` is responsible for
        implementing the naming schema for the newly resized files. All newly
        resized images are formatted with the old file name to which is appended
        the new dimensions and the previous file extension. For example,
        ``Filename 1280×720.png`` from a file previously named ``Filename.png``.
            :param file: The file name of the original file to be reused in the
                new resized file's name
            :param ext: The permissible file extension as retrieved from the
                original image
            :param width: The new width of the resized image to be appended to
                the new file name
            :param height: The new height of the resized image to be appended to
                the new file name
            :return: A new file name string for the resized image
        """

        return f"{str(file)[:-len(ext)]} {str(width)}×{str(height)}{str(ext)}"

    def _format_input(self, data):
        """
        The private ``_format_input`` function serves as a setter helper that
        formats input data that comes packaged as a one-dimension list into a
        nested list construct that is more easily handled and processed in the
        resizing operation. As input data follows the format of file path
        followed by resize factor, i.e. ``['File.jpg', '2', 'File2.png', '5']``,
        the function breaks up associated files and factors into two-element
        nested lists before further subdividing the file into its name and file
        extension. Once the factors are coerced into integers, the modified
        list, formatted ``[[['File', '.jpg'], 2], [['File2', '.png'], 5]]``, is
        then returned to be applied to the class instance's ``data`` attribute.
            :param data: The input data derived from either the command line
                arguments or input entered in the console. Comes packaged as a
                one-dimension list of alternating file paths and resize factors,
                i.e. ``['File.jpg', '2', 'File2.png', '5']``
            :return: A formatted nested list of easier evaluation by the
                resizing functions, formatted as
                ``[[['File', '.jpg'], 2], [['File2', '.png'], 5]]``
        """

        # Ensure each filename and resize value are coupled together in a list
        for pair in (pairs := [data[i:i + 2] for i in range(0, len(data), 2)]):

            # Break filename into list of name and extension
            pair[0] = self._subdivide_file(pair[0])

            # Make sure resize factor expressed as float (throws TypeError)
            pair[1] = abs(float(pair[1]))

            # Prevent images from being resized too large
            if pair[1] > 100:
                pair[1] = 100

        return pairs

    def resize(self):
        """
        The only public function of the class, the ``resize`` function is used
        to perform the resizing operation on the collection of images passed to
        the class instance on initialization as the ``data`` attribute. The
        function for-loops through the multi-dimension list and calls the
        private ``_resize`` function to operate on the images individually.
            :return: None
        """

        for info_list in self.data:
            self._resize(info_list[0], info_list[1])

    @staticmethod
    def _resize(path, factor):
        """
        The private static ``_resize`` function is used as the main catalyst by
        which images denoted in the class instance's ``data`` attributed are
        resized and created as new entities in the present working directory. It
        uses the Pillow module to open the file, grab its present dimensions,
        and perform the resize by multiplying the width and height by the formal
        parameter ``factor``, saving the newly resized image at a new location
        in the present directory for ease of access.
            :param path: The filename of the current file expressed as a two-
                element list containing the name and its file extension
            :param factor: The ``int`` representing the resize factor by which
                the image will be resized. For example, a ``2`` indicates that
                the image should be doubled in size, while ``.5`` indicates it
                should be shrunk to half its present dimensions.
            :return: None
        """

        # May throw IOError for main to catch
        image = PIL.Image.open((file := "".join(path)))

        # Perform the resize, multiplying present dimensions by factor
        width, height = image.size
        image = image.resize((int(width * factor), int(height * factor)))

        # Save the new file at new name in the present directory
        width, height = image.size
        image.save(Resizer._format_filename(file, path[1], width, height))

    def _subdivide_file(self, file):
        """
        The private ``_subdivide_file`` function is a helper function used to
        subdivide the filename/path passed as the ``file`` formal parameter into
        a two-element list composed of the file name and its extension, the
        latter of which retains the period. Given that any number of extensions
        of differing lengths could be used as values of the class instance's
        ``extensions`` list, the function creates a duplicate-free list of their
        respective lengths, iterating through them and checking if the current
        filename has an extension of that length. If so, the file string is
        broken there into a two-element list.
            :param file: The string representing the present file name; for
                example ``Filename.jpg``
            :return subdivided_file: A list containing the file name as the
                first element and the extension with the period as the second;
                for example, ``['Filename', '.jpg']``
        """

        # Calculate extensions lengths, remove duplicates, recast as list
        lengths = list(set(map(lambda ext: len(ext), self.extensions)))
        subdivided_file = []

        # Check if file substring of extension length is in extensions list
        for extension_length in lengths:
            if file[-extension_length:] in self.extensions:
                subdivided_file.insert(0, file[:-extension_length - 1])
                subdivided_file.insert(1, file[-extension_length - 1:])

        # No permissible extension found
        if not len(subdivided_file):
            raise ValueError()

        return subdivided_file


def log_msg(message_text, text_io=sys.stdout):
    """
    The ``log_msg`` function is simply used to log a message in the console
    (expected) using either the ``sys.stdout`` or ``sys.stderr`` text IOs. It
    was intended to behavior much alike to the default ``print`` function but
    with a little more stylistic control.
        :param message_text: A string representing the intended message to print
            to the text IO
        :param text_io: An optional parameter denoting which text IO to which to
            print the ``message_text``. By default, this is ``sys.stdout``.
        :return: None
    """

    text_io.write(f"{message_text}\n")
    text_io.flush()


def main():
    """
    In accordance with convention, the ``main`` function serves simply to
    coordinate the collation of user input and handle the display of status
    messages in the console. It hands off the actual resizing operation
    functionality to the ``Resizer`` class, focusing instead on processing any
    exceptions generated from the class instance's functions in accordance with
    best practice duck typing.
        :return: None
    """

    # Initial definitions
    valid_extensions = ["png", "jpg", "jpeg", "PNG", "JPG"]
    lang = {
        "e_no_data": "Error: No data entered",
        "e_no_resize": "Error: Each file name must have a resize value",
        "e_resize_not_int": "Error: Resize factor must be an int",
        "e_value": "Error: Files must have legitimate extensions and factors",
        "e_unable_to_open": "Error: Unable to open file(s)",
        "s_resized": "Success: All resizes complete"
    }

    # Grab command line arguments or prompt user for input in the console
    if len(sys.argv) > 1:
        input_data = sys.argv[1:]
    elif sys.stdin.isatty():
        input_data = [arg.rstrip() for arg in sys.stdin.readlines()]
    else:
        sys.exit(1)

    # Input is required
    if not len(input_data):
        log_msg(lang["e_no_data"], sys.stderr)
        sys.exit(1)

    # Should be even number of items since each file will have resize value
    if len(input_data) % 2 != 0:
        log_msg(lang["e_no_resize"], sys.stderr)
        sys.exit(1)

    try:
        Resizer(input_data, valid_extensions).resize()
        log_msg(lang["s_resized"], sys.stdout)

    # Thrown by _format_input if factor is not expressible as an int
    except TypeError:
        log_msg(lang["e_resize_not_int"], sys.stderr)

    # Thrown by _subdivide_file if filename has no supported extension
    except ValueError:
        log_msg(lang["e_value"], sys.stderr)

    # Thrown by _resize if the file cannot be opened by PIL.Image.open
    except IOError:
        log_msg(lang["e_unable_to_open"], sys.stderr)
    finally:
        sys.exit(1)


if __name__ == "__main__":
    main()
