import {
  Action,
  ActionPanel,
  Alert,
  Color,
  Icon,
  List,
  Toast,
  confirmAlert,
  showToast,
} from "@raycast/api"
import { useCallback, useEffect, useMemo, useState } from "react"
import { exec } from "child_process"
import { promisify } from "util"

const execAsync = promisify(exec)
const LAYOUTCTL = "/usr/local/bin/layoutctl"

type Profile = {
  profile: string
  createdAt?: string
  updatedAt?: string
}

export default function RestoreLayout() {
  const [profiles, setProfiles] = useState<Profile[]>([])
  const [error, setError] = useState<string>()
  const [isLoading, setIsLoading] = useState(true)
  const [isMutating, setIsMutating] = useState(false)
  const [searchText, setSearchText] = useState("")

  const loadProfiles = useCallback(async () => {
    setIsLoading(true)
    try {
      const { stdout } = await execAsync(`${LAYOUTCTL} list --json`)
      const parsed = JSON.parse(stdout) as Profile[]
      setProfiles(parsed)
      setError(undefined)
    } catch (err) {
      console.error(err)
      setError(
        "Unable to list layouts. Make sure layoutctl is installed and accessible."
      )
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    void loadProfiles()
  }, [loadProfiles])

  const listPlaceholder = useMemo(() => {
    if (error) return "layoutctl error"
    if (!profiles.length) return "No layouts saved yet"
    return "Search layouts…"
  }, [error, profiles])

  const filteredProfiles = useMemo(() => {
    const normalized = searchText.trim().toLowerCase()
    if (!normalized) return profiles
    return profiles.filter((profile) =>
      profile.profile.toLowerCase().includes(normalized)
    )
  }, [profiles, searchText])

  const restoreProfile = async (profile: Profile) => {
    const formatted = profile.profile
    try {
      await execAsync(`${LAYOUTCTL} restore ${escapeArgument(formatted)}`)
      await showToast({
        style: Toast.Style.Success,
        title: `Restored ${formatted}`,
      })
    } catch (err) {
      console.error(err)
      await showToast({
        style: Toast.Style.Failure,
        title: `Failed to restore ${formatted}`,
        message:
          "Check Accessibility permission and make sure layoutctl can move windows.",
      })
    }
  }

  const createProfile = async (name: string) => {
    const formatted = name.trim()
    if (!formatted) return

    setIsMutating(true)
    try {
      await execAsync(`${LAYOUTCTL} save ${escapeArgument(formatted)}`)
      await showToast({
        style: Toast.Style.Success,
        title: `Saved ${formatted}`,
      })
      await loadProfiles()
    } catch (err) {
      console.error(err)
      await showToast({
        style: Toast.Style.Failure,
        title: `Failed to save ${formatted}`,
        message:
          "Check Accessibility permission and make sure layoutctl can move windows.",
      })
    } finally {
      setIsMutating(false)
    }
  }

  const deleteProfile = async (profile: Profile) => {
    const formatted = profile.profile
    const confirmed = await confirmAlert({
      title: `Delete ${formatted}?`,
      message: "This removes the saved layout profile JSON.",
      icon: { source: Icon.Trash, tintColor: Color.Red },
      primaryAction: {
        title: "Delete",
        style: Alert.ActionStyle.Destructive,
      },
    })

    if (!confirmed) return

    setIsMutating(true)
    try {
      await execAsync(`${LAYOUTCTL} delete ${escapeArgument(formatted)}`)
      await showToast({
        style: Toast.Style.Success,
        title: `Deleted ${formatted}`,
      })
      await loadProfiles()
    } catch (err) {
      console.error(err)
      await showToast({
        style: Toast.Style.Failure,
        title: `Failed to delete ${formatted}`,
        message:
          "Ensure layoutctl is installed and that the profile still exists on disk.",
      })
    } finally {
      setIsMutating(false)
    }
  }

  const shouldShowCreateOption =
    !!searchText.trim() &&
    !isLoading &&
    !isMutating &&
    !filteredProfiles.length &&
    !error

  if (error) {
    return (
      <List searchBarPlaceholder={listPlaceholder} isLoading={false}>
        <List.EmptyView
          title="Unable to load layouts"
          description={error}
          icon={{ source: Icon.ExclamationMark, tintColor: Color.Red }}
        />
      </List>
    )
  }

  return (
    <List
      isLoading={isLoading || isMutating}
      searchBarPlaceholder={listPlaceholder}
      isShowingDetail={filteredProfiles.length > 0}
      searchText={searchText}
      onSearchTextChange={setSearchText}
    >
      {filteredProfiles.map((profile) => (
        <List.Item
          key={profile.profile}
          title={profile.profile}
          accessories={
            profile.updatedAt
              ? [
                  {
                    date: new Date(profile.updatedAt),
                    tooltip: `Last updated ${new Date(profile.updatedAt).toLocaleString()}`,
                  },
                ]
              : undefined
          }
          detail={
            <List.Item.Detail
              metadata={
                <List.Item.Detail.Metadata>
                  <List.Item.Detail.Metadata.Label
                    title="Profile"
                    text={profile.profile}
                  />
                  {profile.createdAt && (
                    <List.Item.Detail.Metadata.Label
                      title="Created"
                      text={new Date(profile.createdAt).toLocaleString()}
                    />
                  )}
                  {profile.updatedAt && (
                    <List.Item.Detail.Metadata.Label
                      title="Updated"
                      text={new Date(profile.updatedAt).toLocaleString()}
                    />
                  )}
                </List.Item.Detail.Metadata>
              }
            />
          }
          actions={
            <ActionPanel>
              <Action
                title="Restore Layout"
                icon={Icon.ArrowClockwise}
                onAction={() => restoreProfile(profile)}
              />
              <Action
                title="Delete Layout"
                icon={Icon.Trash}
                style={Action.Style.Destructive}
                onAction={() => void deleteProfile(profile)}
              />
            </ActionPanel>
          }
        />
      ))}
      {shouldShowCreateOption ? (
        <List.Item
          key="create-profile"
          title={`Create "${searchText.trim()}"`}
          icon={Icon.Plus}
          accessories={[
            {
              text: "Save current layout",
            },
          ]}
          actions={
            <ActionPanel>
              <Action
                title={`Save "${searchText.trim()}"`}
                icon={Icon.Plus}
                onAction={() => void createProfile(searchText)}
              />
            </ActionPanel>
          }
        />
      ) : null}
      {!isLoading && !isMutating && !profiles.length && !searchText.trim() ? (
        <List.EmptyView
          title="No layouts found"
          description='Save one with "layoutctl save <profile>" first.'
          icon={Icon.TextDocument}
        />
      ) : null}
    </List>
  )
}

function escapeArgument(arg: string) {
  return `'${arg.replace(/'/g, "'\\''")}'`
}
