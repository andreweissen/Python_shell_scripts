#!/usr/bin/env python

"""
The "Pending Delete" script was developed to be run as a Python shell script
capable of quickly and easily removing pages tagged for pending deletion if the
deletion date posted on the page in a target template matches the present date.
Originally a JavaScript script called "AutoDelete" that was run client-side in
the browser, this script is an improvement on the same concept that is likewise
more conveniently and more quickly run from the command line.
"""

__all__ = [
    "Controller",
    "has_rights",
    "is_fandom_wiki_api_php",
    "log_msg",
    "should_delete"
]
__author__ = "Andrew Eissen"
__version__ = "1.0"

import configparser
import datetime
import json.decoder
import re
import requests
import sys
import time
import urllib.parse


class Controller:
    def __init__(self, api_php, session=None):
        """
        The ``Controller`` class serves to compartmentalize and control all
        interactions with the MediaWiki Action API resource housed at
        ``/api.php``. As the handlers included as methods of the class all make
        use of the same API resource and ``requests.Session`` object instance,
        these are treated as instance fields/attributes universally available
        within the class instance methods for use as needed.
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

    def delete_page(self, page, reason=""):
        """
        The ``delete_page`` function is used to undertake individual page
        deletions via the ``action=delete`` endpoint, accepting a ``page``
        formal parameter denoting the page to delete and an optional ``reason``
        parameter constituting the reason to be logged in the deletion log. As
        there is no "success" condition returned in the JSON data, the function
        checks if a JSON key exclusive to successful deletions is present in the
        JSON and returns an associated boolean value accordingly.
            :param page: The plaintext string representation of the name of the
                page to be deleted.
            :param reason: An optional formal parameter for the deletion reason
                to be logged in the deletion log
            :return: A status boolean denoting whether the operation was
                successfully undertaken. There is no "success" condition
                returned in the JSON data, so the function checks if a JSON key
                that only appears in successful operations is present.
        """

        request = self.session.post(self.api_php, data={
            "action": "delete",
            "title": page,
            "token": self._get_csrf_token(),
            "reason": reason,
            "format": "json"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert("errors" not in data)

        return "logid" in data["delete"]

    def get_category_members(self, category, interval):
        """
        This function is the public-facing method that handles external requests
        for category members. The function collates a master listing of all
        members belonging to the input category specified in the ``category``
        formal parameter list. The function makes use of a recursive private
        helper function that works around maximum return limits imposed by the
        MediaWiki API to ensure all members pages are retrieved together. Prior
        to return, the function removes any duplicate entries found in the
        listing and returns the rest as a list of strings.
            :param category: A string denoting the category from which to
                retrieve member page titles.
            :param interval: The edit interval ensuring operations abide by the
                required rate limit value
            :return members: Though the use of recursive private functions, the
                function returns a master list of category members derived from
                the categories passed in ``category``, bereft of duplicates and
                properly sorted in "human readable" form.
        """

        # If something other than list is passed, raise AssertionError
        assert (isinstance(category, str))

        # wgFormattedNamespaces[14]
        prefix = "Category:"

        # Ensure category string is prefixed with "Category:"
        if not category.startswith(prefix) or category[:len(prefix)] != prefix:
            category = prefix + category

        # Remove duplicate entries via set, then coerce back to list
        members = list(set(self._get_category_members(interval, {
            "cmtitle": category
        })))

        if len(members):
            # Employ human sort (i.e. "Page 2" before "Page 10", not vice versa)
            regex = r"[+-]?([0-9]+(?:[.][0-9]*)?|[.][0-9]+)"
            members.sort(key=lambda m: [float(c) if c.isdigit() else c.lower()
                                        for c in re.split(regex, m)])
        return members

    def _get_category_members(self, interval, config, members=None):
        """
        This function is the primary private helper function employed in the
        category member acquisition process. It is responsible for returning the
        category member pages (articles, templates, other categories, etc.) that
        exist in the given category, the name of which is passed along in the
        ``config`` formal parameter as the value of a key named ``cmtitle``. If
        the maximum number of returned member pages is reached in a given
        ``GET`` request to the ``categorymembers`` endpoint, the function will
        recursively call itself so as to acquire all the pages, eventually
        returning a master list of all members in the parameter category.
            :param interval: The edit interval ensuring operations abide by the
                required rate limit value
            :param config: Depending on the circumstances of the invocation,
                this dictionary may contain the name of the desired category as
                the value of a key titled ``cmtitle`` and/or the value of a key
                titled ``cmcontinue`` indicating where querying should pick up
                should the maximum number of member pages be returned in one
                request.
            :param members: A list of previously collated member pages to be
                returned from the function as the return value
            :return members: Though multiple recursive calls may be made if
                there exist more pages in a category than can be retrieved in a
                single ``GET`` request, the function will ultimately return a
                master list of all members in the given category.
        """

        # Set default for optional parameter
        members = members or []

        # Join config parameter dictionary to params prior to query to pass name
        request = self.session.get(url=self.api_php, params={**{
            "action": "query",
            "list": "categorymembers",
            "cmnamespace": "*",
            "cmprop": "title",
            "cmdir": "desc",
            "cmlimit": "max",
            "rawcontinue": True,
            "format": "json",
        }, **config})

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        for member in data["query"]["categorymembers"]:
            members.append(member["title"])

        # If there are more members than can be retrieved in one call...
        if "query-continue" in data:
            # Sleep to avoid rate limiting...
            time.sleep(interval)

            # ...and recursively call self until all pages are acquired
            self._get_category_members(interval, {**config, **{
                "cmcontinue":
                    data["query-continue"]["categorymembers"]["cmcontinue"]
            }}, members)

        return members

    def _get_csrf_token(self):
        """
        This private function is responsible for acquiring a Cross-Site Request
        Forgery (CSRF) token from the "``tokens``" MediaWiki API endpoint as one
        of the required parameters for all ``POST`` requests made by the
        application. In JavaScript, this token may be acquired simply from
        ``mw.user.tokens.get("editToken")``, but a separate query must be made
        by off-site applications like this one for the purposes of token
        acquisition.
            :return token: A string login token retrieved from the API for use
                in the class's ``POST``ing methods if successful.
        """

        request = self.session.get(url=self.api_php, params={
            "action": "query",
            "meta": "tokens",
            "format": "json"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        token = data["query"]["tokens"]["csrftoken"]

        return token

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

    def get_page_content(self, page):
        """
        The ``get_page_content`` function is used to query the ``action=parse``
        endpoint for the return of the raw wikitext markup of the page passed as
        the ``page`` formal parameter. Within the context of the greater script,
        this content is scanned for the target template containing the pending
        deletion date.
            :param page: The plaintext string representation denoting the page
                from which to retrieve the wikitext content
            :return content: The wikitext content of the given page is returned
                for evaluation and parsing
        """

        request = self.session.get(url=self.api_php, params={
            "action": "parse",
            "prop": "wikitext",
            "page": page,
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

    def get_user_data(self, username):
        """
        The ``get_user_data`` function is used to retrieve information
        pertaining to the user account passed to the function as the formal
        parameter ``username``. The function returns a dictionary containing the
        ``userid`` of the user, the username, and a list containing the
        individual user groups to which the user belongs (i.e. ``sysop``,
        ``content-moderator``, etc.).
            :param username: The string representation of the username of the
                account about which to retrieve information
            :return user: A dictionary containing the ``userid``, ``name``, and
                a ``groups`` list related to the input user is returned
        """

        request = self.session.get(url=self.api_php, params={
            "action": "query",
            "list": "users",
            "ususers": username,
            "usprop": "groups",
            "format": "json"
        })

        # May throw requests.exceptions.HTTPError
        request.raise_for_status()

        # May throw JSONDecodeError
        data = request.json()

        # May throw AssertionError
        assert ("errors" not in data)

        # May throw KeyError
        user = data["query"]["users"][0]

        # May throw AssertionError
        assert("userid" in user and "missing" not in user)

        return user

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


def has_rights(groups, permissible):
    """
    The ``has_rights`` function is used to determine whether the user whose list
    of user rights is passed as the ``groups`` formal parameter possesses the
    required permissions necessary to undertake whatever restricted operation is
    intended. The list produced by ``re.findall`` is coerced into a boolean and
    returned as the returned status of the function.
        :param groups: A list of strings denoting the specific user rights
            groups to which the currently queried user belongs according to the
            MediaWiki API's ``list=users`` endpoint
        :param permissible: A list of strings denoting the target user rights
            against which to compare the user's usergroups for membership
        :return: A boolean denoting whether the user has the permissions
            necessary to undertake whatever operation is intended
    """

    return bool(re.findall(rf'(?=({"|".join(permissible)}))', "|".join(groups)))


def is_fandom_wiki_api_php(url):
    """
    The ``is_fandom_wiki_api_php`` helper function is used to determine whether
    a given URL has a base URL address corresponding to one of the permissible
    Wikia/Fandom domains, namely, ``wikia.org`` and ``fandom.com``. The formal
    parameter, ``url``, is expected to be a base URL, and its subdomain (if any)
    is popped off prior to comparison. A boolean is returned as the return value
    indicating whether the domain of the parameter matches one of the
    Wikia/Fandom default domains and the path points to the ``/api.php``
    resource.
        :param url: A string representing the desired URL for which the function
            will check its base address for compliance with a ``wikia.org`` or
            ``fandom.com`` domain and its path for the ``/api.php`` resource.
        :return: A boolean representing whether the parameter url's base address
            is ``wikia.org`` or ``fandom.com`` is returned
    """

    parsed = urllib.parse.urlparse(url.strip(" "))

    # Only scheme, netloc, and path should be present in base URL
    if (not parsed.scheme or not parsed.netloc or not parsed.path
            or parsed.params or parsed.query or parsed.fragment):
        return False

    # Make sure API resource
    if urllib.parse.urlsplit(url)[2] != "/api.php":
        return False

    # "eizen.fandom.com" -> ["eizen", "fandom", "com"]
    domain = parsed.netloc.split(".")

    # ["eizen", "fandom", "com"] -> ["fandom", "com"]
    domain.pop(0)

    # ["fandom", "com"] -> "fandom.com"
    domain = ".".join(domain)

    return domain in ["fandom.com", "wikia.org"]


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


def should_delete(prompt_message, action_yes="y", action_no="n",
                  action_exit="q"):
    """
    The ``should_delete`` utility function serves to prompt the user to enter an
    accepted value that denotes whether or not to proceed with the given
    deletion operation. Until the user enters one of the accepted booleanesque
    values, the function makes use of a while loop to continuously prompt the
    user accordingly. A status boolean is returned as the result of the function
    operation.
        :param prompt_message: A string representing the message that is to be
            displayed with every prompt iteration
        :param action_yes: An optional formal parameter denoting what the user
            should enter to proceed with the operation
        :param action_no: An optional formal parameter denoting what the user
            should enter to not proceed with the operation
        :param action_exit: An optional formal parameter denoting what the user
            should enter to exit from the application altogether
        :return: A status boolean is returned that indicates whether the user
            intends to proceed with the deletion operation or not.
    """

    while True:
        sys.stdout.write(prompt_message)
        sys.stdout.flush()
        action = sys.stdin.readline().rstrip()

        if action.lower() == action_yes.lower():
            return True
        elif action.lower() == action_no.lower():
            return False
        elif action.lower() == action_exit.lower():
            sys.exit(1)
        else:
            continue


def main():
    """
    As expected from the name, the ``main`` function serves as the central
    coordinating function of the script, handling all user input, calling all
    helper functions, catching all possible generated exceptions, and posting
    results to the specific text IOs as expected.
        :return: None
    """

    # Usergroups that can use the script
    usergroups = [
        "sysop",
        "content-moderator",
        "bot",
        "bot-global",
        "staff",
        "soap",
        "helper",
        "vanguard",
        "wiki-representative",
        "wiki-specialist",
        "content-volunteer"
    ]

    # Collated messages list for display in the console
    lang = {
        "pIntro": "Enter username, password, link to /api.php, target "
                  + "template, and deletion category",
        "pContinue": "Delete anyway? (y/n): ",
        "pAreYouSure": "Delete? (y/n): ",
        "eNoData": "Error: No input data entered",
        "eMissingData": "Error: Missing input data",
        "eURL": "Error: URL is malformed or fails to point to /api.php",
        "eLoginUnknown": "Error: Unable to login despite successful query",
        "eLoginAPI": "Error: Unable to login due to query issues",
        "eLoginRights": "Error: Insufficient user rights on this wiki",
        "eMembersAPI": "Error: Unable to acquire category members due to query "
                       + "issues",
        "eMembersUnknown": "Error: Unable to acquire category members",
        "eNoDeletionDate": "Error: No deletion date found in text of $1",
        "eWikitextAPI": "Error: Unable to acquire wikitext of $1 due to query "
                        + "query issues",
        "eWikitextUnknown": "Error: Unable to acquire wikitext of $1",
        "eDeleteAPI": "Error: Unable to delete $1 due to query issues",
        "eDeleteUnknown": "Error: Unable to delete $1",
        "eDateFormat": "Error: Improperly formatted deletion date for $1 ($2)",
        "eNotToday": "Error: $1 not up for deletion today ($2)",
        "sLogin": "Success: Logged in via bot password",
        "sWikitext": "Success: Acquired wikitext markup of $1",
        "sDeletedPage": "Success: Deleted $1",
        "sToday": "Success: $1 is up for deletion today",
        "sComplete": "Success: All operations complete"
    }

    try:
        # Check if settings.ini file is present
        parser = configparser.ConfigParser()
        parser.read("settings.ini")
        input_data = parser["ENV"].values()
    except KeyError:
        # Check for either command line args or prompt for manual inclusion
        if len(sys.argv) > 1:
            input_data = sys.argv[1:]
        elif sys.stdin.isatty():
            log_msg(lang["pIntro"], sys.stdout)
            input_data = [arg.rstrip() for arg in sys.stdin.readlines()]
        else:
            sys.exit(1)

    # Remove any empty strings from the outset to catch empty input
    input_data = list(filter(None, input_data))

    # Required: username, password, wiki URL, template, category
    if not len(input_data) or len(input_data) < 5:
        log_msg(lang[("eMissingData", "eNoData")[not len(input_data)]],
                sys.stderr)
        sys.exit(1)

    # Unpack the input list
    username, password, wiki_api, template, category = input_data

    # Ensure URL points to valid Fandom wiki's api.php resource
    if not is_fandom_wiki_api_php(wiki_api):
        log_msg(lang["eURL"], sys.stderr)
        sys.exit(1)

    # Create new Controller instance for interaction with the API
    controller = Controller(wiki_api, requests.Session())

    # Definitions
    category_members = []
    is_logged_in = False
    can_delete = False
    delete_anyway = False
    deletion_date = None

    # Formatting/regex-related definitions
    template_regex = r"{{" + template + r"\|(.*)}}"
    date_format = "{dt.day} {dt:%B} {dt.year}"
    parse_format = "%d %B %Y"

    try:
        # Log in, catching bad credentials in the process
        is_logged_in = controller.login(username, password)

        # Grab groups if successful login
        user_data = controller.get_user_data(username)

        # Determine if user has the rights to delete pages
        can_delete = has_rights(user_data["groups"], usergroups)
        if not can_delete:
            log_msg(lang["eLoginRights"], sys.stderr)

    except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
        log_msg(lang["eLoginAPI"], sys.stderr)
    except (AssertionError, KeyError):
        log_msg(lang["eLoginUnknown"], sys.stderr)
    finally:
        # Only proceed with main script if logged in and in right groups
        if is_logged_in and can_delete:
            log_msg(lang["sLogin"], sys.stdout)
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
        # Grab members of deletion cat (cat holding pages marked for deletion)
        category_members = controller.get_category_members(category, interval)
    except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
        log_msg(lang["eMembersAPI"], sys.stderr)
    except (AssertionError, KeyError):
        log_msg(lang["eMembersUnknown"], sys.stderr)
    finally:
        if not len(category_members):
            sys.exit(1)

    for member in category_members:

        log_msg(f"----{member}----", sys.stdout)
        try:
            # Grab raw parsed wikitext markup of each page
            wikitext = controller.get_page_content(member)

            log_msg(lang["sWikitext"].replace("$1", member), sys.stdout)
        except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
            log_msg(lang["eWikitextAPI"].replace("$1", member), sys.stderr)
            continue
        except (AssertionError, KeyError):
            log_msg(lang["eWikitextUnknown"].replace("$1", member), sys.stderr)
            continue
        finally:
            time.sleep(interval)

        # Grab deletion date displayed in transclusions of target template
        template_contents = re.findall(template_regex, wikitext)

        # Log if the deletion date is not found in the template
        if not len(template_contents):
            log_msg(lang["eNoDeletionDate"].replace("$1", member), sys.stderr)
            time.sleep(interval)
            continue

        try:
            # Check if found deletion date follows D M YYYY format
            deletion_date = date_format.format(dt=datetime.datetime.strptime(
                template_contents[0], parse_format))
        except ValueError:
            log_msg(lang["eDateFormat"].replace("$1", member)
                    .replace("$2", template_contents[0]), sys.stderr)
            time.sleep(interval)

            # Prompt user to see if we should continue with the deletion anyway
            delete_anyway = should_delete(lang["pContinue"])
            if not delete_anyway:
                continue
        finally:
            time.sleep(interval)

        # If the user hasn't opted to delete a page with malformed date...
        if not delete_anyway:

            # ...check if today is the day on which the page should be deleted
            if deletion_date != date_format.format(dt=datetime.datetime.now()):
                log_msg(lang["eNotToday"].replace("$1", member)
                        .replace("$2", deletion_date), sys.stderr)
                continue

            # If it is the date, prompt the user for confirmation
            else:
                log_msg(lang["sToday"].replace("$1", member))
                time.sleep(interval)

                if not should_delete(lang["pAreYouSure"]):
                    continue

        try:
            # Attempt to delete the page and log a message if successful
            if controller.delete_page(member):
                log_msg(lang["sDeletedPage"].replace("$1", member), sys.stdout)
        except (requests.exceptions.HTTPError, json.decoder.JSONDecodeError):
            log_msg(lang["eDeleteAPI"].replace("$1", member), sys.stderr)
        except (AssertionError, KeyError):
            log_msg(lang["eDeleteUnknown"].replace("$1", member), sys.stderr)
        finally:
            # Pause execution either way for interval to avoid rate limiting
            time.sleep(interval)

    # Indicate that operations are all complete
    log_msg(lang["sComplete"])


if __name__ == "__main__":
    main()
