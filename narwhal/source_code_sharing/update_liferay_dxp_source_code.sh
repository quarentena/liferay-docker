#!/bin/bash

# shellcheck disable=2002,2013

set -o pipefail

source $(dirname "$(readlink /proc/$$/fd/255 2>/dev/null)")/_liferay_common.sh

BASE_DIR="${PWD}"

REPO_PATH_DXP="${BASE_DIR}/liferay-dxp"
REPO_PATH_EE="${BASE_DIR}/liferay-portal-ee"

TAGS_FILE_DXP="/tmp/tags_file_dxp.txt"
TAGS_FILE_EE="/tmp/tags_file_ee.txt"
TAGS_FILE_NEW="/tmp/tags_file_new.txt"

VERSION="${1}"

function checkout_branch {
	trap 'return ${LIFERAY_COMMON_EXIT_CODE_BAD}' ERR

	local branch_name="${2}"

	lc_cd "${BASE_DIR}/${1}"

	git reset --hard
	git clean -fdX

	if (git show-ref --quiet "${branch_name}")
	then
		git checkout -f -q "${branch_name}"
		git pull origin "${branch_name}"
	else
		git branch "${branch_name}"
		git checkout -f -q "${branch_name}"
	fi
}

function checkout_tag {
	lc_cd "${BASE_DIR}/${1}"

	git checkout "${2}"
}

function commit_and_tag {
	local tag_name="${1}"

	git add .

	git commit -a -m "${tag_name}" -q

	git tag "${tag_name}"
}

function clone_repository {
	if [ -d "${1}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	git clone "git@github.com:liferay/${1}"
}

function fetch_repository {
	lc_cd "${BASE_DIR}/${1}"

	git fetch --all
}

function run_git_maintenance {
	while (pgrep -f "git gc" >/dev/null)
	do
		sleep 1
	done

	rm -f .git/gc.log

	git gc --quiet

	if (! git fsck --full >/dev/null 2>&1)
	then
		echo "Running of 'git fsck' has failed."

		exit 1
	fi
}

function get_all_tags {
	git tag -l --sort=creatordate --format='%(refname:short)' "7.[0-9].1[03]-u[0-9]*"
}

function get_new_tags {
	lc_cd "${REPO_PATH_EE}"

	get_all_tags > "${TAGS_FILE_EE}"

	lc_cd "${REPO_PATH_DXP}"

	get_all_tags > "${TAGS_FILE_DXP}"

	local tag_name

	rm -f "${TAGS_FILE_NEW}"

	# shellcheck disable=SC2013
	for tag_name in $(cat "${TAGS_FILE_EE}")
	do
		if (! grep -qw "${tag_name}" "${TAGS_FILE_DXP}")
		then
			echo "${tag_name}" >> "${TAGS_FILE_NEW}"
		fi
	done
}

function copy_tag {
	local tag_name="${1}"

	lc_time_run checkout_tag liferay-portal-ee "${tag_name}"

	lc_cd "${REPO_PATH_DXP}"

	lc_time_run run_git_maintenance

	lc_time_run run_rsync "${tag_name}"

	lc_time_run commit_and_tag "${tag_name}"
}


function push_to_origin {
	lc_cd "${REPO_PATH_DXP}"

	git push -q origin "${1}"
}

function run_rsync {
	rsync -ar --delete --exclude '.git' "${REPO_PATH_EE}/" "${REPO_PATH_DXP}/"
}

function main {
	LIFERAY_COMMON_LOG_DIR=logs

	lc_time_run clone_repository liferay-dxp

	lc_time_run clone_repository liferay-portal-ee

	lc_time_run fetch_repository liferay-dxp

	lc_time_run fetch_repository liferay-portal-ee

	lc_time_run get_new_tags

	for branch in $(cat "${TAGS_FILE_NEW}" | sed -e "s/-u.*//" | sort -nu)
	do
		for update in $(cat "${TAGS_FILE_NEW}" | grep "^${branch}" | sed -e "s/.*-u//" | sort -n)
		do
			lc_time_run checkout_branch liferay-dxp "${branch}"

			copy_tag "${branch}-u${update}"

			lc_time_run push_to_origin "${branch}-u${update}"

			lc_time_run push_to_origin "${branch}"
		done
	done
}

main "${@}"