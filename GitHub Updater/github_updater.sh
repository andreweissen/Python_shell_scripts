#!/usr/bin/env python

"""
The GitHub Updater is a Python automation script run as a shell script that
permits the automatic updating of repositories housed on GitHub with the
contents of new revisions made to live production code on Fandom's Dev wiki. The
origins of this script lay with its author's manual updating of GitHub mirrors
of his Fandom scripts stored on Dev every time he or another user updated
production code. This script assists in the automation of such processes,
ensuring that all new revisions made to Dev code are reflected in the GitHub
clones as individual commits.
"""

__all__ = []
__author__ = "Andrew Eissen"
__version__ = "1.0"

import base64
import collections
import configparser
import json
import requests
import sys
import time


class Controller:
    def __init__(self, api_php, session=None):
        """
        The ``Controller`` class serves to compartmentalize and control all
        interactions with the MediaWiki Action API resource housed at
        ``/api.php`` and the GitHub API used to update repositories. As the
        handlers included as methods of the class all make use of the same
        MediaWiki API resource and ``requests.Session`` object instance, these
        are treated as instance fields/attributes universally available within
        the class instance methods for use as needed.
            :param api_php: A formatted URL link to the ``/api.php`` resource
                constituting the means by which interactions with the MediaWiki
                Action API may be undertaken.
            :param session: A ``requests.Session`` instance. If one is not
                passed on initialization, a new object is created by the class
                constructor.
        """

        if isinstance(session, type(None)):
            session = requests.Session()

        self.api_php = api_php
        self.session = session

    def get_all_revisions(self, interval, page, rvcontinue=None,
                          revisions=None):
        """
        The ``get_all_revisions`` function is used to retrieve information
        related to the edit revisions associated with the page passed as the
        ``page`` formal parameter. Each revision has its own dictionary that
        contains properties for the editor's username on the wiki and associated
        global ``userid`` as well as the revision's internal ID and parent
        revision's ID (`revid`` and ``parentid``). The page's entire collated
        revisions history is perused and returned as a list of dictionaries from
        the function, making use of recursion if necessary.

        Though a value of "max" is passed as the value of ``rvlimit`` during
        the call to the MediaWiki Action API's ``query`` endpoint, this only
        promises that a max of 500 revisions will be returned from the request.
        If the page has more revisions than this, the function makes use of a
        recursive system similar to that employed in the category member
        acquisition functions likewise included in the ``Controller`` class,
        calling itself and passed the "pick up here" value associated with
        ``rvcontinue`` to ensure all revisions are obtained before they are
        returned in bulk.
            :param interval: The edit interval ensuring operations abide by the
                required rate limit value
            :param page: The name of the page to be queried for its respective
                revision history
            :param rvcontinue: An optional parameter used when recursive calls
                are needed for pages that have more revisions than retrievable
                with one call to indicate where the next call should pick up in
                the revision history
            :param revisions: A list containing the revisions dictionaries,
                passed during recursive calls
            :return revisions: A list of revision dictionaries that each contain
                information pertaining to the editor (name and id) and the
                revision itself (revid and parentid)
        """

        revisions = revisions or []
        params = {
            "action": "query",
            "prop": "revisions",
            "titles": page,
            "rvprop": "ids|user|userid",
            "rvlimit": "max",
            "rvdir": "older",
            "formatversion": "2",
            "format": "json"
        }

        # Used to recursive calls when page's revision count exceeds limit
        if rvcontinue is not None:
            params["rvcontinue"] = rvcontinue

        # Make GET request
        request = self.session.get(url=self.api_php, params=params)

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        revisions = revisions + data["query"]["pages"][0]["revisions"]

        # If there are more revisions than can be retrieved in one call...
        if "continue" in data:
            # Sleep to avoid rate limiting...
            time.sleep(interval)

            # ...and recursively call self until all revisions are acquired
            self.get_all_revisions(interval, page,
                                   data["continue"]["rvcontinue"], revisions)

        return revisions

    def get_last_push_message(self, owner, repo, path, token):
        """
        The ``get_last_push_message`` function is used to retrieve the commit
        message title of the last commit made to the individual file specified
        by the ``path`` formal parameter existing in the GitHub repository
        denoted by the ``repo`` parameter. By the author's conventions, all
        commits made to the repos in question have always followed the naming
        convention of "Special:Diff/12345", an internal reference to the
        MediaWiki revision ID associated with each edit made to production code
        on the Fandom Developers wiki. Retrieving the revision ID of the last
        revision committed to the GitHub mirror assists in determining which new
        revisions should be added to repo to keep it on-track with the Dev
        production code.
            :param owner: The username of the GitHub contributor to whom the
                repository belongs (the author)
            :param repo: The specific GitHub repository housing the code to be
                edited via remote pushes
            :param path: The path to the specific file resource to be edited via
                remote pushes
            :param token: The GitHub application token generated by GitHub for
                use by external applications
            :return: The commit message of the last commit made to the file
                specified by the ``path`` formal parameter
        """

        url = f"https://api.github.com/repos/{owner}/{repo}/commits"
        request = self.session.get(url=url, params={
            "path": path
        }, headers={
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {token}"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw KeyError
        return data[0]["commit"]["message"]

    def _get_login_token(self):
        """
        This private function is used to retrieve a login token from the
        MediaWiki API for use in external, offsite editing/querying. It is used
        in the initial login process by the ``login`` method in conjunction with
        a bot username and password to authenticate the application.
            :return token: A string login token retrieved from the API for use
                in the ``login`` method if successful.
        """

        request = self.session.get(url=self.api_php, params={
            "action": "query",
            "meta": "tokens",
            "type": "login",
            "format": "json"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        token = data["query"]["tokens"]["logintoken"]

        return token

    def get_rate_limit_interval(self):
        """
        This function is responsible for calculating an appropriate edit
        interval that respects the rate limit imposed on the logged-in user. For
        bots and accounts with the bot flag, the limit is 80 edits/minute. For
        standard user accounts, the limit is 40 edits/minute. When calculated,
        these give rise to the edit intervals of .75 seconds and 1.5 seconds,
        respectively.
            :return interval: An appropriate rate limit edit interval is
                returned, as calculated from the values passed by the MediaWiki
                API request
        """

        request = self.session.get(url=self.api_php, params={
            "action": "query",
            "meta": "userinfo",
            "uiprop": "ratelimits",
            "format": "json"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        limits = data["query"]["userinfo"]["ratelimits"]["edit"]["user"]
        interval = limits["seconds"] / limits["hits"]

        return interval

    def get_revision_content(self, revid):
        """
        The ``get_page_content`` function is used to query the ``action=parse``
        endpoint for the return of the raw wikitext markup of the page passed as
        the ``page`` formal parameter. Within the context of the greater script,
        this content is scanned for the target template containing the pending
        deletion date.
            :param revid: The ID associated with a given edit revision on a wiki
                that may or may not be the current revision of a page
            :return content: The wikitext content of the given page is returned
                for evaluation and parsing
        """

        request = self.session.get(url=self.api_php, params={
            "action": "parse",
            "prop": "wikitext",
            "oldid": revid,
            "format": "json"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        content = data["parse"]["wikitext"]["*"]

        return content

    def login(self, username, password):
        """
        The ``login`` function, as the name implies, is used as the primary
        means by which the user logs into the wiki. This function will not
        return a ``True`` status boolean if the user attempts to pass his own
        user account password as the value of the formal parameter of the same
        name; a bot password retrieved from the wiki's ``Special:BotPasswords``
        generator will need to be used for login attempts to succeed.
            :param username: A string representing the username of the user
                employing the application
            :param password: The bot password of the user employing the script,
                obtained from the wiki's ``Special:BotPasswords`` generator
            :return: A status boolean indicating whether the login attempt was
                successful is returned as the return value
        """

        request = self.session.post(self.api_php, data={
            "action": "login",
            "lgname": username,
            "lgpassword": password,
            "lgtoken": self._get_login_token(),
            "format": "json"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        is_successful = data["login"]["result"] == "Success"
        is_right_user = data["login"]["lgusername"] == username

        # Login only occurs if the request succeeds and username matches
        return is_successful and is_right_user

    def update_via_push(self, owner, repo, path, token, new_content,
                        new_message, branch="master"):
        """
        The ``update_via_push`` function serves as the primary mechanism by
        which the script makes remote commits/pushes to the GitHub repository
        mirror specified by means of the ``repo`` formal parameter. The function
        makes a pair of requests, namely a ``GET`` and a ``PUT``, the first of
        which serves to obtain SHA data used in the second. The ``PUT`` request
        updates the extant file in the repo mirror with the encoded new content
        specified in the ``new_content`` formal parameter, applying the value of
        the ``new_message`` param as the commit message title. By convention,
        the message follows the naming convention of Special:Diff/12345 as a
        means of keeping track of the revision IDs of the relevant changes on
        the Fandom Developers wiki.
            :param owner: The username of the GitHub contributor to whom the
                repository belongs (the author)
            :param repo: The specific GitHub repository housing the code to be
                edited via remote pushes
            :param path: The path to the specific file resource to be edited via
                remote pushes
            :param token: The GitHub application token generated by GitHub for
                use by external applications
            :param new_content: The encoded contents of the new commit to be
                pushed to the file specified by the ``path`` formal parameter
            :param new_message: The new commit message title to be associated
                with the new remote commit
            :param branch: The specific branch to which this commit is to be
                applied (optional; "master" by default)
            :return: A boolean denoting whether the operation in question was
                successful (a ``200`` status code)
        """

        url = f"https://api.github.com/repos/{owner}/{repo}/contents/{path}"

        # Encode string content in base 64
        new_content = base64.b64encode(new_content.encode())

        # Primary GET request to acquire SHA info for push
        request = self.session.get(url=url, params={
            "ref": branch
        }, headers={
            "Accept": "application/vnd.github.v3+json",
            "Authorization": f"token {token}"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw KeyError
        sha = data["sha"]

        # Secondary request, a PUT for updating extant file with new content
        request = self.session.put(url=url, data=json.dumps({
            "message": new_message,
            "branch": branch,
            "content": new_content.decode("utf-8"),
            "sha": sha
        }), headers={
            "Accept": "application/vnd.github.v3+json",
            "Content-Type": "application/json",
            "Authorization": f"token {token}"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        return request.status_code == 200


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


def prompt_for_value(message_text):
    """
    The ``prompt_for_value`` function is a helper function built much like
    ``log_msg`` that serves to handle any necessary user input prompts related
    to the acquisition of data beyond the settings config included in the
    ``settings.ini`` file or info passed via command line arguments at program
    initialization.
        :param message_text: A string representing the intended message to print
            to the text IO
        :return: The user input value, a string, is returned from the function
            for external assignment
    """

    sys.stdout.write(f"{message_text}: ")
    sys.stdout.flush()
    return sys.stdin.readline().rstrip()


def main():
    """
    In accordance with best practices, the ``main`` function serves as the
    central coordinating function of the script, handling all user input,
    calling all helper functions, catching all possible generated exceptions,
    and posting results to the specific text IOs as expected.
        :return: None
    """

    # Collated messages list for display in the console
    lang = {
        "p_intro": "Enter Fandom username, Fandom bot password, GitHub name, "
                   + "and GitHub app token",
        "p_file": "Enter Fandom MediaWiki file name on Dev",
        "p_repo": "Enter name of target GitHub repository",
        "p_path": "Enter path to target file in repository",
        "e_missing_data": "Error: Missing input data",
        "e_no_data": "Error: No input data entered",
        "e_login_api": "Error: Unable to login due to API issues",
        "e_login": "Error: Unable to login",
        "e_revisions_api": "Error: Unable to retrieve revisions for \"$1\" due "
                           + "to API issues",
        "e_revisions": "Error: Unable to retrieve revisions for \"$1\"",
        "e_no_revisions": "Error: This page does not exist",
        "e_message_api": "Error: Unable to retrieve last commit message due to "
                         + "API issues",
        "e_message": "Error: Unable to retrieve last commit message",
        "e_up_to_date": "Error: No new revisions; everything is up-to-date",
        "e_adding_diff_api": "Error: Unable to add diff $1 due to API issues",
        "e_adding_diff": "Error: Unable to add diff $1",
        "s_login": "Success: Logged in via bot password",
        "s_revisions": "Success: Retrieved all edit revisions for \"$1\"",
        "s_adding_diff": "Success: Adding new diff $1",
        "s_complete": "Success: All operations complete"
    }

    try:
        # Check if settings.ini file is present
        parser = configparser.ConfigParser()
        parser.read("settings.ini")
        input_data = parser["DEFAULT"].values()
    except KeyError:
        # Check for command line args or prompt for manual inclusion
        if len(sys.argv) > 1:
            input_data = sys.argv[1:]
        elif sys.stdin.isatty():
            log_msg(lang["p_intro"], sys.stdout)
            input_data = [arg.rstrip() for arg in sys.stdin.readlines()]
        else:
            sys.exit(1)

    # Remove any empty strings from the outset to catch empty input
    input_data = list(filter(None, input_data))

    # Required: GitHub username and token
    if not len(input_data) or len(input_data) < 4:
        log_msg(lang[("e_missing_data", "e_no_data")[not len(input_data)]],
                sys.stderr)
        sys.exit(1)

    # Unpack the input list
    username, password, name, token = input_data

    # Dev wiki API (for acquisition of MediaWiki files housed there)
    api_php = "https://dev.fandom.com/api.php"

    # Get Fandom MediaWiki file (i.e. "MediaWiki:Custom-MassEdit/i18n.json")
    file = prompt_for_value(lang["p_file"])

    # Get repo name (i.e. "GitHub_API_test_repo" or "MassEdit")
    repo = prompt_for_value(lang["p_repo"])

    # Get path to file from repo home (i.e. "code/i18n.json")
    path = prompt_for_value(lang["p_path"])

    # Create new Fandom/MediaWiki/GitHub controller object
    controller = Controller(api_php, requests.Session())

    # Definitions
    is_logged_in = False
    add_these_revisions = collections.deque()

    try:
        # Log in, catching bad credentials in the process
        is_logged_in = controller.login(username, password)
    except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
        log_msg(lang["e_login_api"], sys.stderr)
    except (AssertionError, KeyError):
        log_msg(lang["e_login"], sys.stderr)
    finally:
        # Only proceed with main script if logged in and in right groups
        if is_logged_in:
            log_msg(lang["s_login"], sys.stdout)
        else:
            sys.exit(1)

    try:
        # Calculate interval from API limits...
        interval = controller.get_rate_limit_interval()
    except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError,
            AssertionError, KeyError):
        # ...or apply default 1500 ms value
        interval = 1.5
    time.sleep(interval)

    try:
        # Grab authorship info for all revisions related to MediaWiki file
        revisions = controller.get_all_revisions(interval, file)
        log_msg(lang["s_revisions"].replace("$1", file), sys.stdout)
    except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
        log_msg(lang["e_revisions_api"].replace("$1", file), sys.stderr)
        sys.exit(1)
    except (AssertionError, KeyError):
        log_msg(lang["e_revisions"].replace("$1", file), sys.stderr)
        sys.exit(1)
    finally:
        time.sleep(interval)

    # Should never be encountered, but just in case...
    if not len(revisions):
        log_msg(lang["e_no_revisions"], sys.stderr)
        return

    try:
        # Retrieve message formatted as "Special:Diff/123456"
        last_commit_msg = controller.get_last_push_message(name, repo, path,
                                                           token)
    except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
        log_msg(lang["e_message_api"], sys.stderr)
        sys.exit(1)
    except KeyError:
        log_msg(lang["e_message"], sys.stderr)
        sys.exit(1)
    finally:
        time.sleep(interval)

    # Iterate over revisions from the newest to oldest, collating a listing of
    # revisions on Fandom that have not yet been committed to GitHub
    for index, revision in enumerate(revisions):

        # Format as "Special:Diff/123456"
        new_commit_msg = f'Special:Diff/{str(revision["revid"])}'

        # Check if current revision has already been committed to GitHub
        if new_commit_msg == last_commit_msg:

            # If the most recent revision is already on GitHub, nothing to do
            if index == 0:
                log_msg(lang["e_up_to_date"], sys.stderr)
                sys.exit(1)

            # Otherwise, exit loop, as all pending revisions have been acquired
            break

        # If the most recent commit hasn't been found, add latest to front of
        # deque as the oldest revision
        add_these_revisions.appendleft(revision["revid"])

    if not len(add_these_revisions):
        log_msg(lang["e_up_to_date"], sys.stderr)
        return

    # For all revisions that haven't been added to GitHub, start with oldest,...
    for revid in add_these_revisions:
        revid = str(revid)
        try:
            # ...attempt to push revision to GitHub from Fandom and...
            controller.update_via_push(name, repo, path, token,
                                       controller.get_revision_content(revid),
                                       f"Special:Diff/{revid}")
            # ...log message if successful
            log_msg(lang["s_adding_diff"].replace("$1", revid), sys.stdout)
        except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
            log_msg(lang["e_adding_diff_api"].replace("$1", revid), sys.stderr)
        except KeyError:
            log_msg(lang["e_adding_diff"].replace("$1", revid), sys.stderr)
        finally:
            time.sleep(interval)

    # Indicate that operations are all complete
    log_msg(lang["s_complete"])


if __name__ == "__main__":
    main()
