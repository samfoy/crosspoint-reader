#pragma once

#include <functional>
#include <string>
#include <vector>

#include "../Activity.h"
#include "RecentBooksStore.h"
#include "util/ButtonNavigator.h"

class FileBrowserActivity final : public Activity {
 private:
  // Deletion
  void clearFileMetadata(const std::string& fullPath);

  ButtonNavigator buttonNavigator;

  size_t selectorIndex = 0;

  // Files state
  std::string basepath = "/";
  std::string focusName;  // entry to select on first load (e.g. the file just returned from)
  std::vector<std::string> files;

  // In-folder text filter. Empty => no filter active. Applied to `files` in-place
  // after loadFiles() so existing rendering code needs no changes.
  std::string filterQuery;

  // Data loading
  void loadFiles();
  size_t findEntry(const std::string& name) const;

  // Filtering
  void applyFilter();      // narrows `files` to entries matching filterQuery
  void launchFilter();     // opens the soft keyboard to edit filterQuery
  void onFilterResult(const std::string& query);

 public:
  explicit FileBrowserActivity(GfxRenderer& renderer, MappedInputManager& mappedInput, std::string initialPath = "/",
                               std::string focusName = {})
      : Activity("FileBrowser", renderer, mappedInput),
        basepath(initialPath.empty() ? "/" : std::move(initialPath)),
        focusName(std::move(focusName)) {}
  void onEnter() override;
  void onExit() override;
  void loop() override;
  void render(RenderLock&&) override;
};
