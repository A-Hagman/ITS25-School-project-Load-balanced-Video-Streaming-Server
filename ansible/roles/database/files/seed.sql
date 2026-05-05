CREATE TABLE IF NOT EXISTS videos (
    id SERIAL PRIMARY KEY,
    videotitle VARCHAR(255) NOT NULL,
    filepath VARCHAR(255) NOT NULL,
    uploadedate DATE NOT NULL,
    views INTEGER DEFAULT 0
);

INSERT INTO videos (videotitle, filepath, uploadedate, views)
VALUES (
    'How to Nitflix and chill',
    'http://192.168.56.15/videos/nitflix.mp4',
    '1969-07-06',
    67
) ON CONFLICT DO NOTHING;