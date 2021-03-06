/* Copyright 2013-2015 Robert Schroll
 * Copyright 2018-2020 Emanuele Sorce
 *
 * This file is part of Beru and is distributed under the terms of
 * the GPL. See the file COPYING for full details.
 */

import QtQuick 2.4
import QtQuick.LocalStorage 2.0
import QtGraphicalEffects 1.0
import Ubuntu.Components 1.3
import Ubuntu.Components.ListItems 1.3
import Ubuntu.Components.Popups 1.3

import "components"


Page {
    id: localBooks

    flickable: gridview

    property int sort: localBooks.header.extension.selectedIndex
    property bool needsort: false
    property bool firststart: false
    property bool wide: false
    property string bookdir: ""
    property bool readablehome: false
    property string defaultdirname: i18n.tr("Books")
    property double gridmargin: units.gu(1)
    property double mingridwidth: units.gu(15)
    property bool reloading: false

    onSortChanged: {
        listBooks()
        perAuthorModel.clear()
        adjustViews(false)
    }
    onWidthChanged: {
        wide = (width >= units.gu(80))
        widthAnimation.enabled = false
        adjustViews(true)  // True to allow author's list if necessary
        widthAnimation.enabled = true
    }
    
    function onFirstStart(db) {
        db.changeVersion(db.version, "1")
        noBooksLabel.text = i18n.tr("Welcome to Sturm Reader!")
        firststart = true
    }

    function openDatabase() {
        return LocalStorage.openDatabaseSync("BeruLocalBooks", "", "Books on the local device",
                                             1000000, onFirstStart);
    }
    
    function fileToTitle(filename) {
        return filename.replace(/\.\w+$/, "").replace(/_/g, " ")
    }
    
    // New items are given a lastread time of now, since these are probably
    // interesting for a user to see.
    property string addFileSQL: "INSERT OR IGNORE INTO LocalBooks(filename, title, author, authorsort, " +
                                "cover, lastread) VALUES(?, ?, '', 'zzznull', 'ZZZnone', datetime('now'))"

    function addFile(filePath, startCoverTimer) {
        var fileName = filePath.split("/").pop()
        var db = openDatabase()
        db.transaction(function (tx) {
            tx.executeSql(addFileSQL, [filePath, fileToTitle(fileName)])
        })
        localBooks.needsort = true
        if (startCoverTimer)
            coverTimer.start()
    }

    function addBookDir() {
        var db = openDatabase()
        db.transaction(function (tx) {
            var files = filesystem.listDir(bookdir, ["*.epub", "*.cbz", "*.pdf"])
            for (var i=0; i<files.length; i++) {
                var fileName = files[i].split("/").pop()
                tx.executeSql(addFileSQL, [files[i], fileToTitle(fileName)])
            }
        })
        localBooks.needsort = true
    }
    
    function listBooks() {
        // We only need to GROUP BY in the author sort, but this lets us use the same
        // SQL logic for all three cases.
        var sort = ["GROUP BY filename ORDER BY lastread DESC, title ASC",
                    "GROUP BY filename ORDER BY title ASC",
                    "GROUP BY authorsort ORDER BY authorsort ASC"][localBooks.sort]
        if (sort === undefined) {
            console.log("Error: Undefined sorting: " + localBooks.sort)
            return
        }

        listview.delegate = (localBooks.sort == 2) ? authorDelegate : titleDelegate

        bookModel.clear()
        var db = openDatabase()
        db.readTransaction(function (tx) {
            var res = tx.executeSql("SELECT filename, title, author, cover, fullcover, authorsort, count(*) " +
                                    "FROM LocalBooks " + sort)
            for (var i=0; i<res.rows.length; i++) {
                var item = res.rows.item(i)
                if (filesystem.exists(item.filename))
                    bookModel.append({filename: item.filename, title: item.title,
                                      author: item.author, cover: item.cover, fullcover: item.fullcover,
                                      authorsort: item.authorsort, count: item["count(*)"]})
            }
        })
        localBooks.needsort = false
    }

    function listAuthorBooks(authorsort) {
        perAuthorModel.clear()
        var db = openDatabase()
        db.readTransaction(function (tx) {
            var res = tx.executeSql("SELECT filename, title, author, cover, fullcover FROM LocalBooks " +
                                    "WHERE authorsort=? ORDER BY title ASC", [authorsort])
            for (var i=0; i<res.rows.length; i++) {
                var item = res.rows.item(i)
                if (filesystem.exists(item.filename))
                    perAuthorModel.append({filename: item.filename, title: item.title,
                                           author: item.author, cover: item.cover, fullcover: item.fullcover})
            }
            perAuthorModel.append({filename: "ZZZback", title: i18n.tr("Back"),
                                   author: "", cover: ""})
        })
    }

    function updateRead(filename) {
        var db = openDatabase()
        db.transaction(function (tx) {
            tx.executeSql("UPDATE OR IGNORE LocalBooks SET lastread=datetime('now') WHERE filename=?",
                          [filename])
        })
        if (localBooks.sort == 0)
            listBooks()
    }

    function updateBookCover() {
        var db = openDatabase()
        db.transaction(function (tx) {
            var res = tx.executeSql("SELECT filename, title FROM LocalBooks WHERE authorsort == 'zzznull'")
            if (res.rows.length == 0)
                return

            localBooks.needsort = true
            var title, author, authorsort, cover, fullcover, hash
            if (coverReader.load(res.rows.item(0).filename)) {
                var coverinfo = coverReader.getCoverInfo(units.gu(5), 2*mingridwidth)
                title = coverinfo.title
                if (title == "ZZZnone")
                    title = res.rows.item(0).title

                author = coverinfo.author.trim()
                authorsort = coverinfo.authorsort.trim()
                if (authorsort == "zzznone" && author != "") {
                    // No sort information, so let's do our best to fix it:
                    authorsort = author
                    var lc = author.lastIndexOf(",")
                    if (lc == -1) {
                        // If no commas, assume "First Last"
                        var ls = author.lastIndexOf(" ")
                        if (ls > -1) {
                            authorsort = author.slice(ls + 1) + ", " + author.slice(0, ls)
                            authorsort = authorsort.trim()
                        }
                    } else if (author.indexOf(",") == lc) {
                        // If there is exactly one comma in the author, assume "Last, First".
                        // Thus, authorsort is correct and we have to fix author.
                        author = author.slice(lc + 1).trim() + " " + author.slice(0, lc).trim()
                    }
                }

                cover = coverinfo.cover
                fullcover = coverinfo.fullcover
                hash = coverReader.hash()
            } else {
                title = res.rows.item(0).title
                author = i18n.tr("Could not open this book.")
                authorsort = "zzzzerror"
                cover = "ZZZerror"
                fullcover = ""
                hash = ""
            }
            tx.executeSql("UPDATE LocalBooks SET title=?, author=?, authorsort=?, cover=?, " +
                          "fullcover=?, hash=? WHERE filename=?",
                          [title, author, authorsort, cover, fullcover, hash, res.rows.item(0).filename])

            if (localBooks.visible) {
                for (var i=0; i<bookModel.count; i++) {
                    var book = bookModel.get(i)
                    if (book.filename == res.rows.item(0).filename) {
                        book.title = title
                        book.author = author
                        book.cover = cover
                        book.fullcover = fullcover
                        break
                    }
                }
            }

            coverTimer.start()
        })
    }

    function refreshCover(filename) {
        var db = openDatabase()
        db.transaction(function (tx) {
            tx.executeSql("UPDATE LocalBooks SET authorsort='zzznull' WHERE filename=?", [filename])
        })

        coverTimer.start()
    }

    function inDatabase(hash, existsCallback, newCallback) {
        var db = openDatabase()
        db.readTransaction(function (tx) {
            var res = tx.executeSql("SELECT filename FROM LocalBooks WHERE hash == ?", [hash])
            if (res.rows.length > 0 && filesystem.exists(res.rows.item(0).filename))
                existsCallback(res.rows.item(0).filename)
            else
                newCallback()
        })
    }

    function readBookDir() {
        reloading = true
        addBookDir()
        listBooks()
        coverTimer.start()
        reloading = false
    }

    function adjustViews(showAuthor) {
        if (sort != 2 || perAuthorModel.count == 0)
            showAuthor = false  // Don't need to show authors' list

        if (sort == 0) {
            listview.visible = false
            gridview.visible = true
            localBooks.flickable = gridview
        } else {
            listview.visible = true
            gridview.visible = false
            if (!wide || sort != 2) {
                listview.width = localBooks.width
                listview.x = showAuthor ? -localBooks.width : 0
                localBooks.flickable = showAuthor ? perAuthorListView : listview
            } else {
                localBooks.flickable = null
                listview.width = localBooks.width / 2
                listview.x = 0
                listview.topMargin = 0
                perAuthorListView.topMargin = 0
            }
        }
    }

    function loadBookDir() {
        if (filesystem.readableHome()) {
            readablehome = true
            var storeddir = getSetting("bookdir")
            bookdir = (storeddir == null) ? filesystem.getDataDir(defaultdirname) : storeddir
        } else {
            readablehome = false
            bookdir = filesystem.getDataDir(defaultdirname)
        }
    }	

    function setBookDir(dir) {
        bookdir = dir
        setSetting("bookdir", dir)
    }

    Component.onCompleted: {
        var db = openDatabase()
        db.transaction(function (tx) {
            tx.executeSql("CREATE TABLE IF NOT EXISTS LocalBooks(filename TEXT UNIQUE, " +
                          "title TEXT, author TEXT, cover BLOB, lastread TEXT)")
        })
        // NOTE: db.version is not updated live!  We will get the change only the next time
        // we run, so here we must keep track of what's been happening.  onFirstStart() has
        // already run, so we're at version 1, even if db.version is empty.
        if (db.version == "" || db.version == "1") {
            db.changeVersion(db.version, "2", function (tx) {
                tx.executeSql("ALTER TABLE LocalBooks ADD authorsort TEXT NOT NULL DEFAULT 'zzznull'")
            })
        }
        if (db.version == "" || db.version == "1" || db.version == "2") {
            db.changeVersion(db.version, "3", function (tx) {
                tx.executeSql("ALTER TABLE LocalBooks ADD fullcover BLOB DEFAULT ''")
                // Trigger re-rendering of covers.
                tx.executeSql("UPDATE LocalBooks SET authorsort='zzznull'")
            })
        }
        if (db.version == "" || db.version == "1" || db.version == "2" || db.version == "3") {
            db.changeVersion(db.version, "4", function (tx) {
                tx.executeSql("ALTER TABLE LocalBooks ADD hash TEXT DEFAULT ''")
                // Trigger re-evaluation to update hashes.
                tx.executeSql("UPDATE LocalBooks SET authorsort='zzznull'")
            })
        }
    }

    // We need to wait for main to be finished, so that the settings are available.
    function onMainCompleted() {
        // readBookDir() will trigger the loading of all files in the default directory
        // into the library.
        if (!firststart) {
            loadBookDir()
            readBookDir()
        } else {
            readablehome = filesystem.readableHome()
            if (readablehome) {
                setBookDir(filesystem.homePath() + "/" + defaultdirname)
                PopupUtils.open(settingsComponent)
            } else {
                setBookDir(filesystem.getDataDir(defaultdirname))
                readBookDir()
            }
        }
    }

    // If we need to resort, do it when hiding or showing this page
    onVisibleChanged: {
        if (needsort)
            listBooks()
        // If we are viewing recently read, then the book we had been reading is now at the top
        if (visible && sort == 0)
            gridview.positionViewAtBeginning()
    }

    Reader {
        id: coverReader
    }

    Timer {
        id: coverTimer
        interval: 1000
        repeat: false
        running: false
        triggeredOnStart: false

        onTriggered: localBooks.updateBookCover()
    }
    
    ListModel {
        id: bookModel
    }

    ListModel {
        id: perAuthorModel
        property bool needsclear: false
    }

    DefaultCover {
        id: defaultCover
    }

    header: PageHeader {
        id: header
        title: i18n.tr("Library")

        trailingActionBar {
            actions: [
                Action {
                    text: i18n.tr("Get Books")
                    iconName: "add"
					onTriggered: pageStack.push(importer.pickerPage)
                },
                Action {
                    text: i18n.tr("About")
                    iconName: "info"
					onTriggered: pageStack.push(about)
                },
                Action {
                    text: i18n.tr("Settings")
                    iconName: "settings"
                    onTriggered: {
                        if (localBooks.readablehome)
                            PopupUtils.open(settingsComponent)
                        else
                            PopupUtils.open(settingsDisabledComponent)
                    }
                }

            ]
        }
        extension: Sections {
            id: hsections
            model: [i18n.tr("Recently Read"), i18n.tr("Title"), i18n.tr("Author")]
            anchors {
                left: parent.left
                bottom: parent.bottom
                leftMargin: units.gu(2)
            }
        }
    }


    Component {
        id: coverDelegate
        Item {
            width: gridview.cellWidth
            height: gridview.cellHeight

            Item {
                id: image
                anchors.fill: parent

                Image {
                    anchors {
                        fill: parent
                        leftMargin: gridmargin
                        rightMargin: gridmargin
                        topMargin: 1.5*gridmargin
                        bottomMargin: 1.5*gridmargin
                    }
                    fillMode: Image.PreserveAspectFit
                    source: {
                        if (model.cover == "ZZZerror")
                            return defaultCover.errorCover(model)
                        if (!model.fullcover)
                            return defaultCover.missingCover(model)
                        return model.fullcover
                    }
                    // Prevent blurry SVGs
                    sourceSize.width: 2*localBooks.mingridwidth
                    sourceSize.height: 3*localBooks.mingridwidth

                    Text {
                        x: ((model.cover == "ZZZerror") ? 0.09375 : 0.125)*parent.width
                        y: 0.0625*parent.width
                        width: 0.8125*parent.width
                        height: parent.height/2 - 0.125*parent.width
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        color: defaultCover.textColor(model)
                        style: Text.Raised
                        styleColor: defaultCover.highlightColor(model, defaultCover.hue(model))
                        font.family: "URW Bookman L"
                        text: {
                            if (!model.fullcover)
                                return model.title
                            return ""
                        }
                    }

                    Text {
                        x: ((model.cover == "ZZZerror") ? 0.09375 : 0.125)*parent.width
                        y: parent.height/2 + 0.0625*parent.width
                        width: 0.8125*parent.width
                        height: parent.height/2 - 0.125*parent.width
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        color: defaultCover.textColor(model)
                        style: Text.Raised
                        styleColor: defaultCover.highlightColor(model, defaultCover.hue(model))
                        font.family: "URW Bookman L"
                        text: {
                            if (!model.fullcover)
                                return model.author
                            return ""
                        }
                    }
                }
            }

            DropShadow {
                anchors.fill: image
                radius: 1.5*gridmargin
                samples: 16
                source: image
                color: UbuntuColors.graphite
                verticalOffset: 0.25*gridmargin
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    // Save copies now, since these get cleared by loadFile (somehow...)
                    var filename = model.filename
                    var pasterror = model.cover == "ZZZerror"
                    if (loadFile(filename) && pasterror)
                        refreshCover(filename)
                }
                onPressAndHold: openInfoDialog(model)
            }
        }
    }

    Component {
        id: titleDelegate
        Subtitled {
            text: model.title
            subText: model.author
            iconSource: {
                if (model.filename == "ZZZback")
                    return "image://theme/back"
                if (model.cover == "ZZZnone")
                    return defaultCover.missingCover(model)
                if (model.cover == "ZZZerror")
                    return Qt.resolvedUrl("images/error_cover.svg")
                return model.cover
            }
            iconFrame: model.filename != "ZZZback" && model.cover != "ZZZerror"
            visible: model.filename != "ZZZback" || !wide
            progression: false
            onClicked: {
                if (model.filename == "ZZZback") {
                    perAuthorModel.needsclear = true
                    adjustViews(false)
                } else {
                    // Save copies now, since these get cleared by loadFile (somehow...)
                    var filename = model.filename
                    var pasterror = model.cover == "ZZZerror"
                    if (loadFile(filename) && pasterror)
                        refreshCover(filename)
                }
            }
            onPressAndHold: {
                if (model.filename != "ZZZback")
                    openInfoDialog(model)
            }
        }
    }

    Component {
        id: authorDelegate
        Subtitled {
            text: model.author || i18n.tr("Unknown Author")
            /*/ Argument will be at least 2. /*/
            subText: (model.count > 1) ? i18n.tr("%1 Book", "%1 Books", model.count).arg(model.count)
                                       : model.title
            iconSource: {
                if (model.count > 1)
                    return "image://theme/contact"
                if (model.cover == "ZZZnone")
                    return defaultCover.missingCover(model)
                if (model.cover == "ZZZerror")
                    return Qt.resolvedUrl("images/error_cover.svg")
                return model.cover
            }
            iconFrame: model.count == 1 && model.cover != "ZZZerror"
            progression: model.count > 1
            onClicked: {
                if (model.count > 1) {
                    listAuthorBooks(model.authorsort)
                    adjustViews(true)
                } else {
                    // Save copies now, since these get cleared by loadFile (somehow...)
                    var filename = model.filename
                    var pasterror = model.cover == "ZZZerror"
                    if (loadFile(filename) && pasterror)
                        refreshCover(filename)
                }
            }
            onPressAndHold: {
                if (model.count == 1)
                    openInfoDialog(model)
            }
        }
    }

    ListView {
        id: listview
        x: 0

        anchors {
            top: header.bottom
        }

        height: parent.height
        width: parent.width

        clip: true

        model: bookModel

        Behavior on x {
            id: widthAnimation
            NumberAnimation {
                duration: UbuntuAnimation.BriskDuration
                easing: UbuntuAnimation.StandardEasing

                onRunningChanged: {
                    if (!running && perAuthorModel.needsclear) {
                        perAuthorModel.clear()
                        perAuthorModel.needsclear = false
                    }
                }
            }
        }

        PullToRefresh {
            refreshing: reloading
            onRefresh: readBookDir()
        }
    }

    Scrollbar {
        flickableItem: listview
        align: Qt.AlignTrailing
    }

    ListView {
        id: perAuthorListView
        anchors {
            left: listview.right
            top: header.bottom
        }
        width: wide ? parent.width / 2 : parent.width
        height: parent.height
        clip: true

        model: perAuthorModel
        delegate: titleDelegate
    }

    Scrollbar {
        flickableItem: perAuthorListView
        align: Qt.AlignTrailing
    }

    GridView {
        id: gridview
        anchors {
            top: header.bottom
            left: parent.left
            right: parent.right
            leftMargin: gridmargin
            rightMargin: gridmargin
        }
        height: mainView.height
        clip: true
        cellWidth: width / Math.floor(width/mingridwidth)
        cellHeight: cellWidth*1.5

        model: bookModel
        delegate: coverDelegate

        PullToRefresh {
            refreshing: reloading
            onRefresh: readBookDir()
        }
    }

    Scrollbar {
        flickableItem: gridview
        align: Qt.AlignTrailing
        anchors {
            right: localBooks.right
            top: header.bottom
            bottom: localBooks.bottom
        }
    }

    Item {
        anchors.fill: parent
        visible: bookModel.count == 0

        Column {
            anchors.centerIn: parent
            spacing: units.gu(2)
            width: Math.min(units.gu(30), parent.width)

            Label {
                id: noBooksLabel
                text: i18n.tr("No Books in Library")
                fontSize: "large"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            Label {
                /*/ A path on the file system. /*/
                text: i18n.tr("Sturm Reader could not find any books for your library, and will " +
                              "automatically find all epub files in <i>%1</i>.  Additionally, any book " +
                              "opened will be added to the library.").arg(bookdir)
                wrapMode: Text.Wrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            StyledButton {
                text: i18n.tr("Get Books")
                width: parent.width
                onClicked: pageStack.push(bookSources)
            }

            StyledButton {
                text: i18n.tr("Search Again")
                width: parent.width
                onClicked: readBookDir()
            }
        }
    }



    function openInfoDialog(book) {
        var dialog = PopupUtils.open(infoComponent)
        dialog.bookTitle = book.title
        dialog.filename = book.filename

        var dirs = ["/.local/share/%1", "/.local/share/ubuntu-download-manager/%1"]
        for (var i=0; i<dirs.length; i++) {
            var path = filesystem.homePath() + dirs[i].arg(mainView.applicationName)
            if (dialog.filename.slice(0, path.length) == path) {
                dialog.allowDelete = true
                break
            }
        }

        if (book.cover == "ZZZerror")
            dialog.coverSource = defaultCover.errorCover(book)
        else if (!book.fullcover)
            dialog.coverSource = defaultCover.missingCover(book)
        else
            dialog.coverSource = book.fullcover
    }

    Component {
        id: infoComponent

        Dialog {
            id: infoDialog

            property alias coverSource: infoCover.source
            property alias bookTitle: titleLabel.text
            property alias filename: filenameLabel.text
            property alias allowDelete: swipe.visible

            Item {
                height: Math.max(infoCover.height, infoColumn.height)

                Image {
                    id: infoCover
                    width: parent.width / 3
                    height: parent.width / 2
                    anchors {
                        left: parent.left
                        top: parent.top
                    }
                    fillMode: Image.PreserveAspectFit
                    // Prevent blurry SVGs
                    sourceSize.width: 2*localBooks.mingridwidth
                    sourceSize.height: 3*localBooks.mingridwidth
                }

                Column {
                    id: infoColumn
                    anchors {
                        left: infoCover.right
                        right: parent.right
                        top: parent.top
                        leftMargin: units.gu(2)
                    }
                    spacing: units.gu(2)

                    Label {
                        id: titleLabel
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        fontSize: "large"
                        color: UbuntuColors.darkGrey
                        wrapMode: Text.Wrap
                    }
                    Label {
                        id: filenameLabel
                        width: parent.width
                        horizontalAlignment: Text.AlignLeft
                        fontSize: "small"
                        color: UbuntuColors.darkGrey
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }

            SwipeControl {
                id: swipe
                visible: false
                /*/ A control can be dragged to delete a file.  The deletion occurs /*/
                /*/ when the user releases the control. /*/
                actionText: i18n.tr("Release to Delete")
                /*/ A control can be dragged to delete a file. /*/
                notificationText: i18n.tr("Swipe to Delete")
                onTriggered: {
                    filesystem.remove(infoDialog.filename)
                    PopupUtils.close(infoDialog)
                    readBookDir()
                }
            }

            StyledButton {
                text: i18n.tr("Close")
                onClicked: PopupUtils.close(infoDialog)
            }
        }
    }

    Component {
        id: settingsComponent

        Dialog {
            id: settingsDialog
            title: firststart ? i18n.tr("Welcome to Sturm Reader!") : i18n.tr("Default Book Location")
            /*/ Text precedes an entry for a file path. /*/
            text: i18n.tr("Enter the folder in your home directory where your ebooks are or " +
                          "should be stored.\n\nChanging this value will not affect existing " +
                          "books in your library.")
            property string homepath: filesystem.homePath() + "/"

            TextField {
                id: pathfield
                text: {
                    if (bookdir.substring(0, homepath.length) == homepath)
                        return bookdir.substring(homepath.length)
                    return bookdir
                }
                onTextChanged: {
                    var status = filesystem.exists(homepath + pathfield.text)
                    if (status == 0) {
                        /*/ Create a new directory from path given. /*/
                        useButton.text = i18n.tr("Create Directory")
                        useButton.enabled = true
                    } else if (status == 1) {
                        /*/ File exists with path given. /*/
                        useButton.text = i18n.tr("File Exists")
                        useButton.enabled = false
                    } else if (status == 2) {
                        if (homepath + pathfield.text == bookdir && !firststart)
                            /*/ Read the books in the given directory again. /*/
                            useButton.text = i18n.tr("Reload Directory")
                        else
                            /*/ Use directory specified to store books. /*/
                            useButton.text = i18n.tr("Use Directory")
                        useButton.enabled = true
                    }
                }
            }

            StyledButton {
                id: useButton
                onClicked: {
                    var status = filesystem.exists(homepath + pathfield.text)
                    if (status != 1) { // Should always be true
                        if (status == 0)
                            filesystem.makeDir(homepath + pathfield.text)
                        setBookDir(homepath + pathfield.text)
                        useButton.enabled = false
                        useButton.text = i18n.tr("Please wait...")
                        cancelButton.enabled = false
                        unblocker.start()
                    }
                }
            }

            Timer {
                id: unblocker
                interval: 10
                onTriggered: {
                    readBookDir()
                    PopupUtils.close(settingsDialog)
                    firststart = false
                }
            }

            StyledButton {
                id: cancelButton
                text: i18n.tr("Cancel")
                primary: false
                visible: !firststart
                onClicked: PopupUtils.close(settingsDialog)
            }
        }
    }

    Component {
        id: settingsDisabledComponent

        Dialog {
            id: settingsDisabledDialog
            title: i18n.tr("Default Book Location")
            /*/ A path on the file system. /*/
            text: i18n.tr("Sturm Reader seems to be operating under AppArmor restrictions that prevent it " +
                             "from accessing most of your home directory.  Ebooks should be put in " +
                             "<i>%1</i> for Sturm Reader to read them.").arg(bookdir)

            StyledButton {
                text: i18n.tr("Reload Directory")
                // We don't bother with the Timer trick here since we don't get this dialog on
                // first launch, so we shouldn't have too many books added to the library when
                // this button is clicked.s
                onClicked: {
                    PopupUtils.close(settingsDisabledDialog)
                    readBookDir()
                }
            }

            StyledButton {
                text: i18n.tr("Close")
                primary: false
                onClicked: PopupUtils.close(settingsDisabledDialog)
            }
        }
    }
}
