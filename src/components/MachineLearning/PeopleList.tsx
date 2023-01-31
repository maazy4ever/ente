import React, { useState, useEffect } from 'react';
import { Face, Person } from 'types/machineLearning';
import {
    getAllPeople,
    getPeopleList,
    getUnidentifiedFaces,
} from 'utils/machineLearning';
import styled from 'styled-components';
import { EnteFile } from 'types/file';
import { ImageCacheView } from './ImageViews';
import { FACE_CROPS_CACHE } from 'constants/cache';
import { Legend } from 'components/PhotoViewer/styledComponents/Legend';
import constants from 'utils/strings/constants';
import { addLogLine } from 'utils/logging';

const FaceChipContainer = styled.div`
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    align-items: center;
    margin-top: 5px;
    margin-bottom: 5px;
    overflow: auto;
`;

const FaceChip = styled.div`
    width: 112px;
    height: 112px;
    margin: 5px;
    border-radius: 50%;
    overflow: hidden;
    position: relative;
    cursor: pointer;

    & > img {
        width: 100%;
        height: 100%;
    }
`;

interface PeopleListPropsBase {
    onSelect?: (person: Person, index: number) => void;
}

export interface PeopleListProps extends PeopleListPropsBase {
    people: Array<Person>;
    maxRows?: number;
}

export function PeopleList(props: PeopleListProps) {
    return (
        <FaceChipContainer
            style={
                props.maxRows && {
                    maxHeight: props.maxRows * 122 + 28,
                }
            }>
            {props.people.map((person, index) => (
                <FaceChip
                    key={index}
                    onClick={() =>
                        props.onSelect && props.onSelect(person, index)
                    }>
                    <ImageCacheView
                        url={person.displayImageUrl}
                        cacheName={FACE_CROPS_CACHE}
                    />
                </FaceChip>
            ))}
        </FaceChipContainer>
    );
}

export interface PhotoPeopleListProps extends PeopleListPropsBase {
    file: EnteFile;
    updateMLDataIndex: number;
}

export function PhotoPeopleList(props: PhotoPeopleListProps) {
    const [people, setPeople] = useState<Array<Person>>([]);

    useEffect(() => {
        let didCancel = false;

        async function updateFaceImages() {
            addLogLine('calling getPeopleList');
            const startTime = Date.now();
            const people = await getPeopleList(props.file);
            addLogLine('getPeopleList', Date.now() - startTime, 'ms');
            addLogLine('getPeopleList done, didCancel: ', didCancel);
            !didCancel && setPeople(people);
        }

        updateFaceImages();

        return () => {
            didCancel = true;
        };
    }, [props.file, props.updateMLDataIndex]);

    if (people.length === 0) return <></>;

    return (
        <div>
            <Legend>{constants.PEOPLE}</Legend>
            <PeopleList people={people} onSelect={props.onSelect}></PeopleList>
        </div>
    );
}

export interface AllPeopleListProps extends PeopleListPropsBase {
    limit?: number;
}

export function AllPeopleList(props: AllPeopleListProps) {
    const [people, setPeople] = useState<Array<Person>>([]);

    useEffect(() => {
        let didCancel = false;

        async function updateFaceImages() {
            let people = await getAllPeople();
            if (props.limit) {
                people = people.slice(0, props.limit);
            }
            !didCancel && setPeople(people);
        }

        updateFaceImages();

        return () => {
            didCancel = true;
        };
    }, [props.limit]);

    return <PeopleList people={people} onSelect={props.onSelect}></PeopleList>;
}

export function UnidentifiedFaces(props: {
    file: EnteFile;
    updateMLDataIndex: number;
}) {
    const [faces, setFaces] = useState<Array<Face>>([]);

    useEffect(() => {
        let didCancel = false;

        async function updateFaceImages() {
            const faces = await getUnidentifiedFaces(props.file);
            !didCancel && setFaces(faces);
        }

        updateFaceImages();

        return () => {
            didCancel = true;
        };
    }, [props.file, props.updateMLDataIndex]);

    if (!faces || faces.length === 0) return <></>;

    return (
        <>
            <div>
                <Legend>{constants.UNIDENTIFIED_FACES}</Legend>
            </div>
            <FaceChipContainer>
                {faces &&
                    faces.map((face, index) => (
                        <FaceChip key={index}>
                            <ImageCacheView
                                url={face.crop?.imageUrl}
                                cacheName={FACE_CROPS_CACHE}
                            />
                        </FaceChip>
                    ))}
            </FaceChipContainer>
        </>
    );
}
