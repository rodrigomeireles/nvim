import runpy
import sys

CPPMAN_SCRIPT = "/mnt/c/Users/rodri/scoop/apps/python311/current/Scripts/cppman"


def find_arg(argv, *names):
    for idx, arg in enumerate(argv):
        if arg in names:
            return idx
    return None


def handle_find(argv):
    idx = find_arg(argv, "-f", "--find-page")
    if idx is None or idx + 1 >= len(argv):
        return None

    pattern = argv[idx + 1]
    max_results = -1
    max_idx = find_arg(argv, "-n", "--max-results")
    if max_idx is not None and max_idx + 1 < len(argv):
        try:
            max_results = int(argv[max_idx + 1])
        except ValueError:
            max_results = -1

    from cppman.main import Cppman

    cm = Cppman()
    results = cm._search_keyword(pattern)
    if max_results >= 1:
        results = results[:max_results]

    if not results:
        print(f"{pattern}: nothing appropriate.", file=sys.stderr)
        return 16

    for name, keyword, _url in results:
        print(f"{keyword} - {name}")
    return 0


def main():
    find_status = handle_find(sys.argv[1:])
    if find_status is not None:
        return find_status

    sys.argv = [CPPMAN_SCRIPT] + sys.argv[1:]
    runpy.run_path(CPPMAN_SCRIPT, run_name="__main__")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
