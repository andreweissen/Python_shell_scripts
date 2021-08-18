#!/usr/bin/env python

"""
The Retuner script serves as a convenient means of adjusting the pitch and/or
speed of a given audio file. The script makes use of the pydub and librosa
libraries/modules to either adjust the pitch of a file by semitonal intervals or
both the pitch and the playback speed. The latter retains the audio quality of
the original file, though it produces a "chipmunks" quality that the former
manages to avoid.
"""

__all__ = ["Retuner", "log_msg"]
__author__ = "Andrew Eissen"
__version__ = "0.1"

import librosa
import pydub
import os
import soundfile
import sys


class Retuner:
    def __init__(self, path, steps, sample_rate=44100):
        """
        The ``Retuner`` class encapsulates the functions responsible for
        adjusting the pitch and/or speed of a given audio track denoted by the
        ``path`` formal parameter by the number of semitones specified by
        ``steps``. The ``sample_rate`` parameter, an optional param, is set to
        the industry standard 44100 by default. The class makes use of the
        librosa library for the adjustment of pitch without simultaneous
        adjustment of speed, while the pydub library is used to adjust the two
        in concert to preserve audio quality.
            :param path: The path to the audio file. Ideally, this file should
                be a ``wav`` file, though the script will convert ``mp3``s.
            :param steps: The number of semitones by which to pitch-adjust the
                audio track (C -> C#, for example)
            :param sample_rate: An optional parameter denoting the sample rate
                at which to export the file, set to industry-standard 44100 by
                default
        """

        extension = os.path.splitext(path)[1]
        file_name = os.path.splitext(path)[0]

        # Convert MP3 files to WAV for ease of pitch adjustment
        if extension.lower() == ".mp3":
            sound = pydub.AudioSegment.from_mp3(path)
            sound.export(f"{file_name}.wav", format="wav")
            path = f"{file_name}.wav"

        self.file_name = file_name
        self.path = path
        self.steps = float(steps)
        self.sample_rate = int(sample_rate)

    def pitch_shift_and_adjust_speed(self):
        """
        The ``pitch_shift_and_adjust_speed`` function makes use of the ``pydub``
        library's functionality to undertake semitonal pitch shifts that occur
        in concert with playback speed changes. The function creates a new file
        at a new name for the adjusted audio file, following the format
        "``Filename_[number of steps].wav``".
            :return: None
        """

        sound = pydub.AudioSegment.from_file(self.path, format="wav")
        new_sound = sound._spawn(sound.raw_data, overrides={
            "frame_rate": int(sound.frame_rate * (2.0 ** (self.steps / 12.0)))
        })
        new_sound = new_sound.set_frame_rate(self.sample_rate)
        new_sound.export(f"{self.file_name}_{self.steps}.wav", format="wav")

    def pitch_shift(self):
        """
        The ``pitch_shift`` function makes use of the librosa library's
        functionality to undertake the semitonal adjustment of an audio file's
        pitch without making simultaneous adjustments to playback speed. The
        function creates a new file at a new name for the adjusted audio file,
        following the format "``Filename_[number of steps].wav``".
            :return: None
        """

        y, sr = librosa.load(self.path, sr=self.sample_rate)
        y_shifted = librosa.effects.pitch_shift(y, sr, n_steps=self.steps)
        soundfile.write(f"{self.file_name}_{str(self.steps)}.wav", y_shifted,
                        self.sample_rate, "PCM_24")


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
    In accordance with best practices, the ``main`` function serves as the
    central coordinating function of the script, handling all user input,
    calling all helper functions, catching all possible generated exceptions,
    and posting results to the specific text IOs as expected.
        :return: None
    """

    lang = {
        "p_intro": "Enter file path, number of steps by which to transpose, "
                   + "and whether or not to adjust both speed and pitch",
        "e_steps": "Error: Second value must be of a number type",
        "e_adjust_both": "Third value must be of type boolean",
        "e_no_file": "Error: No audio file found by that name",
        "i_converting": "Converting...",
        "s_complete": "Success: Conversion complete"
    }

    # Accept either command line args or console input
    if len(sys.argv) > 1:
        input_data = sys.argv[1:]
    elif sys.stdin.isatty():
        log_msg(lang["p_intro"], sys.stdout)
        input_data = [arg.rstrip() for arg in sys.stdin.readlines()]
    else:
        sys.exit(1)

    # Unpack input values
    path, steps, adjust_both = input_data

    # Ensure steps and adjustment flag are of proper types
    try:
        steps = float(steps)
        adjust_both = eval(adjust_both)
    except ValueError:
        log_msg(lang["e_steps"], sys.stderr)
        sys.exit(1)
    except NameError:
        log_msg(lang["e_adjust_both"], sys.stderr)
        sys.exit(1)

    log_msg(lang["i_converting"], sys.stdout)
    try:
        # Only adjust pitch, not speed, if adjust_both is False
        getattr(Retuner(path, steps),
                ("pitch_shift", "pitch_shift_and_adjust_speed")[adjust_both])()
        log_msg(lang["s_complete"], sys.stdout)
    except FileNotFoundError:
        log_msg(lang["e_no_file"], sys.stderr)


if __name__ == "__main__":
    main()
