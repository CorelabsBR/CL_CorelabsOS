import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 15000
        running: true
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }
    Slide {
        Image {
            id: image1
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "01.png"
        }
    }
    Slide {
        Image {
            id: image2
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "02.png"
        }
    }
    Slide {
        Image {
            id: image3
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "03.png"
        }
    }
    Slide {
        Image {
            id: image4
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "04.png"
        }
    }
    Slide {
        Image {
            id: image5
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "05.png"
        }
    }
    Slide {
        Image {
            id: image6
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "06.png"
        }
    }
    Slide {
        Image {
            id: image7
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "07.png"
        }
    }
    Slide {
        Image {
            id: image8
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "08.png"
        }
    }
    Slide {
        Image {
            id: image9
            anchors.centerIn: parent
            anchors.verticalCenterOffset: - parent.y / 3.6
            height: parent.masterHeight * 0.95
            width: parent.masterWidth * 0.95
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "09.png"
        }
    }
}
